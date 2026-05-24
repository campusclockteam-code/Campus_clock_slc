import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FCMService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static bool _isInitialized = false;

  // ==================== INITIALIZATION ====================

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request notification permissions
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('✅ Notification permission status: ${settings.authorizationStatus}');

      // Get FCM token
      final String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print('✅ FCM Token: $token');

        // Subscribe to topic
        await _firebaseMessaging.subscribeToTopic('all_users');
        print('✅ Subscribed to topic: all_users');

        // Save token to Firestore if user is logged in
        final User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await saveTokenToFirestore(user.uid);
        }

        // Listen for token refresh
        _firebaseMessaging.onTokenRefresh.listen((String newToken) {
          print('🔄 Token refreshed: $newToken');
          _updateTokenInFirestore(newToken);
        });

        _isInitialized = true;
      } else {
        print('⚠️ FCM token not available - notifications disabled');
      }
    } catch (e) {
      print('⚠️ FCM not available: $e');
      // Continue without FCM - app will still work
    }
  }

  // ==================== LOCAL NOTIFICATIONS (IN-APP) ====================

  static void showCustomNotification({
    required String title,
    required String body,
    required BuildContext context,
  }) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  // ==================== TOKEN MANAGEMENT ====================

  static Future<void> _updateTokenInFirestore(String token) async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ Token updated in Firestore');
      }
    } catch (e) {
      print('Error updating token: $e');
    }
  }

  static Future<void> saveTokenToFirestore(String userId) async {
    try {
      final String? token = await _firebaseMessaging.getToken();
      if (token != null && userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        print('✅ Token saved for user: $userId');
      }
    } catch (e) {
      print('Error saving token: $e');
    }
  }

  // ==================== SEND NOTIFICATIONS ====================

  static Future<Map<String, dynamic>> sendNotificationsToGroup({
    required String message,
    required String targetGroup,
    required String senderName,
    required String title,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      Query query = FirebaseFirestore.instance.collection('users');

      if (targetGroup == 'teachers') {
        query = query.where('role', isEqualTo: 'teacher');
      } else if (targetGroup == 'students') {
        query = query.where('role', isEqualTo: 'student');
      }

      final QuerySnapshot usersSnapshot = await query.get();

      if (usersSnapshot.docs.isEmpty) {
        return {'successfulSends': 0, 'message': 'No users found'};
      }

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      List<String> notificationIds = [];

      for (QueryDocumentSnapshot userDoc in usersSnapshot.docs) {
        final Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        final String userId = userDoc.id;
        final String userEmail = userData['email'] as String? ?? '';

        final DocumentReference notificationRef = FirebaseFirestore.instance
            .collection('notifications')
            .doc();

        notificationIds.add(notificationRef.id);

        batch.set(notificationRef, {
          'message': message,
          'title': title,
          'senderName': senderName,
          'targetGroup': targetGroup,
          'userId': userId,
          'userEmail': userEmail,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
          'type': 'admin_message',
          'notificationId': notificationRef.id,
          ...?additionalData,
        });
        count++;

        if (count % 500 == 0) {
          await batch.commit();
          print('✅ Committed batch of $count notifications to Firestore');
        }
      }

      if (count % 500 != 0) {
        await batch.commit();
        print('✅ Committed final batch of $count notifications to Firestore');
      }

      // Save to admin_messages for tracking
      final adminMessageRef = await FirebaseFirestore.instance
          .collection('admin_messages')
          .add({
        'message': message,
        'targetGroup': targetGroup,
        'title': title,
        'senderName': senderName,
        'timestamp': FieldValue.serverTimestamp(),
        'totalRecipients': usersSnapshot.docs.length,
        'status': 'sent',
        'type': 'admin_message',
        'notificationIds': notificationIds,
      });

      print('✅ Saved $count notifications to Firestore');

      return {
        'successfulSends': usersSnapshot.docs.length,
        'totalDevices': usersSnapshot.docs.length,
        'failedSends': 0,
        'message': 'Notifications saved successfully!',
        'adminMessageId': adminMessageRef.id,
      };

    } catch (e) {
      print('❌ Error sending notifications: $e');
      return {
        'successfulSends': 0,
        'totalDevices': 0,
        'failedSends': 0,
        'error': e.toString(),
        'message': 'Failed to send notifications',
      };
    }
  }

  static Future<Map<String, dynamic>> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    required String senderName,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      // Get user data
      final DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        return {
          'success': false,
          'error': 'User not found',
        };
      }

      final Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      final String userEmail = userData['email'] as String? ?? '';

      // Save to Firestore notifications collection
      final DocumentReference notificationRef = await FirebaseFirestore.instance
          .collection('notifications')
          .add({
        'message': body,
        'title': title,
        'senderName': senderName,
        'targetGroup': 'single_user',
        'userId': userId,
        'userEmail': userEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'type': 'direct_message',
        ...?additionalData,
      });

      print('✅ Notification saved for user: $userId');

      return {
        'success': true,
        'notificationId': notificationRef.id,
      };

    } catch (e) {
      print('❌ Error saving notification: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ==================== NOTIFICATION MANAGEMENT ====================

  static Future<int> getUnreadNotificationsCount(String userId) async {
    try {
      final AggregateQuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      print('✅ Notification marked as read: $notificationId');
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  static Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .get();

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (QueryDocumentSnapshot doc in snapshot.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      print('✅ Marked ${snapshot.docs.length} notifications as read');
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  static Future<void> deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .delete();
      print('✅ Notification deleted: $notificationId');
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  static Future<void> deleteOldNotifications({int daysOld = 30}) async {
    try {
      final DateTime cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('timestamp', isLessThan: cutoffDate)
          .limit(100)
          .get();

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (QueryDocumentSnapshot doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('✅ Deleted ${snapshot.docs.length} old notifications');
    } catch (e) {
      print('Error deleting old notifications: $e');
    }
  }

  // ==================== TOPIC SUBSCRIPTIONS ====================

  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('Error subscribing to topic: $e');
    }
  }

  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing from topic: $e');
    }
  }

  // ==================== STREAMS ====================

  static Stream<QuerySnapshot> getUserNotifications(String userId) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot> getAllAdminMessages() {
    return FirebaseFirestore.instance
        .collection('admin_messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
