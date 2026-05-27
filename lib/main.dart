import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campus_clock_slc/service/fcm_service.dart';
import 'Home/splash_screen.dart';
import 'Entry/login_page.dart';
import 'service/notifications_screen.dart';
import 'Entry/signup_page.dart';
import 'Home/Home_page.dart';
import 'Admin/AdminScreen.dart';
import 'Timetable/home_screen.dart';

// Handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
  print('Message title: ${message.notification?.title}');
  print('Message body: ${message.notification?.body}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize FCM Service
  await FCMService.initialize();

  // Request notification permissions
  NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  print('Notification permission: ${settings.authorizationStatus}');

  // Get FCM token
  String? token = await FirebaseMessaging.instance.getToken();
  print('✅ FCM Token: $token');

  // Subscribe to topics
  await FirebaseMessaging.instance.subscribeToTopic('all_users');
  print('✅ Subscribed to all_users topic');

  // Handle foreground messages (app is open)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('📱 Got a message while in foreground!');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');

    // Show in-app notification using your FCMService
    if (message.notification != null && message.notification!.title != null) {
      // You can show a dialog or use your existing method
      // For now, let's show a SnackBar
      // This will be visible when app is open
    }
  });

  // Handle when app is opened from a terminated state
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    print('App opened from terminated state by notification');
  }

  // Handle when app is in background and opened by notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('App opened from background by notification');
    // Navigate to specific screen if needed
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Clock',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => const HomePage(),
        '/timetable': (context) => const HomeScreen(),
        '/admin': (context) => const AdminScreen(),
        '/notifications': (context) => const NotificationsScreen(),
      },
    );
  }
}
