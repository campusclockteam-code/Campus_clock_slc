import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../Service/fcm_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = false;
  bool _hasMore = true;
  int _unreadCount = 0;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final count = await FCMService.getUnreadNotificationsCount(user.uid);
      setState(() {
        _unreadCount = count;
      });
    }
  }

  Future<void> _markAllAsRead() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark All as Read'),
        content: Text('Mark all $_unreadCount notifications as read?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Mark All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await FCMService.markAllNotificationsAsRead(user.uid);
        setState(() => _unreadCount = 0);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshNotifications() async {
    _loadUnreadCount();
    // Stream will automatically refresh
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final String? userId = user?.uid;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
            if (_unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        elevation: 0.5,
        actions: [
          if (_unreadCount > 0)
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.done_all),
              onPressed: _isLoading ? null : _markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _clearOldNotifications(isDarkMode),
            tooltip: 'Clear old notifications',
          ),
        ],
      ),
      body: userId == null || userId.isEmpty
          ? _buildNotLoggedInWidget(isDarkMode)
          : RefreshIndicator(
        onRefresh: _refreshNotifications,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _refreshNotifications(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyWidget(isDarkMode);
            }

            final notifications = snapshot.data!.docs;

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final doc = notifications[index];
                final data = doc.data() as Map<String, dynamic>;
                final bool isRead = data['read'] == true;
                final String title = data['title'] ?? 'Notification';
                final String message = data['message'] ?? '';
                final dynamic timestamp = data['timestamp'];
                final String sender = data['senderName'] ?? 'Campus Clock';
                final String type = data['type'] ?? 'general';

                return Dismissible(
                  key: Key(doc.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) => _deleteNotification(doc.id, isDarkMode),
                  child: _buildNotificationCard(
                    doc.id,
                    title,
                    message,
                    sender,
                    timestamp,
                    isRead,
                    type,
                    isDarkMode,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
      String id,
      String title,
      String message,
      String sender,
      dynamic timestamp,
      bool isRead,
      String type,
      bool isDarkMode,
      ) {
    String timeAgo = '';
    String formattedDate = '';

    if (timestamp != null) {
      final date = timestamp is Timestamp ? timestamp.toDate() : DateTime.now();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 7) {
        formattedDate = DateFormat('MMM d, yyyy').format(date);
        timeAgo = formattedDate;
      } else if (diff.inDays > 0) {
        timeAgo = '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        timeAgo = '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        timeAgo = '${diff.inMinutes}m ago';
      } else {
        timeAgo = 'Just now';
      }
    }

    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'admin_message':
        iconData = Icons.admin_panel_settings;
        iconColor = Colors.purple;
        break;
      case 'timetable_update':
        iconData = Icons.schedule;
        iconColor = Colors.green;
        break;
      case 'attendance':
        iconData = Icons.check_circle;
        iconColor = Colors.orange;
        break;
      default:
        iconData = Icons.notifications;
        iconColor = isRead ? Colors.grey : Colors.blue;
    }

    return GestureDetector(
      onTap: () => _markAsRead(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isRead
              ? (isDarkMode ? Colors.grey[850] : Colors.white)
              : (isDarkMode ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05)),
          border: Border(
            bottom: BorderSide(color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isRead ? (isDarkMode ? Colors.grey[800] : Colors.grey[200]) : iconColor.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(iconData, color: isRead ? Colors.grey : iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                      fontSize: 15,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: isDarkMode ? Colors.grey[500] : Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        sender,
                        style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.grey[500] : Colors.grey[500]),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.access_time, size: 12, color: isDarkMode ? Colors.grey[500] : Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.grey[500] : Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsRead(String docId) async {
    try {
      await FCMService.markNotificationAsRead(docId);
      setState(() {
        if (_unreadCount > 0) _unreadCount--;
      });
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> _deleteNotification(String docId, bool isDarkMode) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      _loadUnreadCount();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearOldNotifications(bool isDarkMode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Old Notifications'),
        content: const Text('Delete all notifications older than 30 days?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await FCMService.deleteOldNotifications(daysOld: 30);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Old notifications cleared'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildNotLoggedInWidget(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Not Signed In',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to see your notifications',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.login),
            label: const Text('Sign In'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Notifications',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When you receive notifications, they will appear here',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}