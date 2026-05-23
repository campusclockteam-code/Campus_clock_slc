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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();
  // Initialize FCM Service (this handles permissions, token, and notifications)
  await FCMService.initialize();
  // Get FCM token for debugging
  String? token = await FirebaseMessaging.instance.getToken();
  print('✅ FCM Token: $token');
  // Subscribe to general topics
  await FirebaseMessaging.instance.subscribeToTopic('all_users');
  print('✅ Subscribed to all_users topic');

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
      // Handle navigation when notification is tapped
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/notification':
          // Navigate to notification details page if needed
            return MaterialPageRoute(
              builder: (context) => const HomePage(),
            );
          default:
            return null;
        }
      },
    );
  }
}