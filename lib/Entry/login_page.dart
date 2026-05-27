import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../Animation/animated_background.dart';
import '../service/fcm_service.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _showSuccess = false;
  String _successMessage = '';
  Timer? _successTimer;

  // Hardcoded admin credentials
  static const String adminUsername = 'Admin';
  static const String adminEmail = 'admin@campusclock.com';
  static const String adminPassword = '20170024656';

  @override
  void initState() {
    super.initState();
    _initializeFCM();
  }

  Future<void> _initializeFCM() async {
    await FCMService.initialize();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _successTimer?.cancel();
    super.dispose();
  }

  Future<String?> _getEmailFromRollNumber(String rollNumber) async {
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('rollNumber', isEqualTo: rollNumber)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        return userSnapshot.docs.first.data()['email'] as String?;
      }

      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('rollNo', isEqualTo: rollNumber)
          .limit(1)
          .get();

      if (studentSnapshot.docs.isNotEmpty) {
        final studentData = studentSnapshot.docs.first.data();
        if (studentData.containsKey('email') && studentData['email'] != null) {
          return studentData['email'] as String;
        }
      }

      return null;
    } catch (e) {
      print('Error finding email from roll number: $e');
      return null;
    }
  }

  Future<void> _setupAdminInFirestore(UserCredential adminCredential) async {
    try {
      // Create/update admin user in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(adminCredential.user!.uid)
          .set({
        'isAdmin': true,
        'role': 'admin',
        'email': adminEmail,
        'displayName': 'Admin',
        'userName': 'Admin',
        'studentName': 'Admin',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Admin user created/updated in Firestore');

      // Also create in students collection for any student-related queries
      await FirebaseFirestore.instance
          .collection('students')
          .doc(adminCredential.user!.uid)
          .set({
        'isAdmin': true,
        'role': 'admin',
        'email': adminEmail,
        'displayName': 'Admin',
        'name': 'Admin',
        'rollNo': 'ADMIN001',
      }, SetOptions(merge: true));

      print('✅ Admin also added to students collection');
    } catch (e) {
      print('Error setting up admin in Firestore: $e');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      String identifier = _identifierController.text.trim();
      String password = _passwordController.text.trim();

      // CHECK FOR ADMIN - BOTH USERNAME AND EMAIL
      if ((identifier == adminUsername || identifier == adminEmail) &&
          password == adminPassword) {
        print('✅ Admin logged in');

        // Sign in or create admin in Firebase Auth
        UserCredential? adminCredential;
        try {
          // Try to sign in existing admin
          adminCredential =
              await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: adminEmail,
            password: adminPassword,
          );
          print('✅ Admin signed in to Firebase Auth');
        } catch (e) {
          // If admin doesn't exist, create it
          print('Admin not found in Auth, creating...');
          adminCredential =
              await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: adminEmail,
            password: adminPassword,
          );
          print('✅ Admin created in Firebase Auth');
        }

        // Setup admin in Firestore
        if (adminCredential != null) {
          await _setupAdminInFirestore(adminCredential);
        }

        final prefs = await SharedPreferences.getInstance();

        // Clear all previous data first
        await prefs.clear();

        // Set ALL admin data
        await prefs.setBool('has_logged_in', true);
        await prefs.setString('user_name', 'Admin');
        await prefs.setString('user_email', adminEmail);
        await prefs.setBool('is_admin', true);
        await prefs.setBool('is_teacher', false);
        await prefs.setBool('is_guest', false);
        await prefs.setString('user_role', 'admin');
        await prefs.setString('student_name', 'Admin');
        await prefs.setString('user_gender', 'Other');
        await prefs.setString('user_id', adminCredential.user!.uid);

        // Clear any student/teacher specific data
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_semester');
        await prefs.remove('student_gender');
        await prefs.remove('teacher_name');

        // Verify admin data was saved
        print('=== Admin Data Saved ===');
        print('is_admin: ${prefs.getBool('is_admin')}');
        print('user_role: ${prefs.getString('user_role')}');
        print('user_name: ${prefs.getString('user_name')}');
        print('student_name: ${prefs.getString('student_name')}');
        print('user_email: ${prefs.getString('user_email')}');
        print('user_id: ${prefs.getString('user_id')}');
        print('========================');

        FCMService.showCustomNotification(
          title: 'Admin Login 👑',
          body: 'Welcome to Admin Dashboard!',
          context: context,
        );
        _showSuccessMessage('Welcome Admin!');
        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          // Navigate to home - HomePage will detect admin role
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
        }
        return;
      }

      // For regular users - determine if identifier is roll number or email
      String email;

      // Check if identifier is numeric (roll number)
      if (RegExp(r'^\d+$').hasMatch(identifier)) {
        final foundEmail = await _getEmailFromRollNumber(identifier);
        if (foundEmail == null) {
          _showError('No account found with this roll number');
          return;
        }
        email = foundEmail;
      }
      // Check if identifier is email format
      else if (RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(identifier)) {
        email = identifier;
      } else {
        _showError('Please enter a valid email, roll number, or "Admin"');
        return;
      }

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        _showError('User data not found. Please contact support.');
        return;
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      bool isAdmin = userData['isAdmin'] == true ||
          email.toLowerCase() == 'surajncc2006@gmail.com';

      String role = 'student';
      if (isAdmin) {
        role = 'admin';
      } else {
        role = userData['role'] ?? 'student';
      }

      String displayName = userData['displayName'] ??
          (userData['teacherName'] ?? userData['studentName'] ?? 'User');

      final prefs = await SharedPreferences.getInstance();

      // Clear previous data
      await prefs.clear();

      // Set basic user info
      await prefs.setBool('has_logged_in', true);
      await prefs.setString('user_email', email);
      await prefs.setString('user_name', displayName);
      await prefs.setString('user_gender', userData['gender'] ?? 'Other');
      await prefs.setBool('is_teacher', role == 'teacher');
      await prefs.setBool('is_admin', isAdmin);
      await prefs.setBool('is_guest', false);
      await prefs.setString('user_id', userCredential.user!.uid);
      await prefs.setString(
          'profile_photo_url', userData['profilePhotoUrl'] ?? '');
      await prefs.setString('user_role', role);
      await prefs.setString('student_name', displayName);

      // Store role-specific data
      if (role == 'student') {
        final rollNumber =
            userData['rollNumber'] ?? (userData['rollNo']?.toString() ?? '');
        final course = userData['course'] ?? '';
        final semester =
            userData['semester'] ?? userData['currentSemester'] ?? 1;
        final year = userData['year'] ?? '';
        final section = userData['section'] ?? '';

        await prefs.setString('roll_number', rollNumber);
        await prefs.setString('selected_course', course);
        await prefs.setInt('selected_semester', _parseSemesterNumber(semester));
        await prefs.setString('selected_year', year);
        await prefs.setString('selected_section', section);
        await prefs.setString('student_gender', userData['gender'] ?? '');
        await prefs.remove('teacher_name');

        print('✅ Student data saved:');
        print('   Roll Number: $rollNumber');
        print('   Course: $course');
        print('   Semester: $semester');
        print('   Year: $year');
        print('   Section: $section');
      } else if (role == 'teacher') {
        final teacherName = userData['teacherName'] ?? displayName;
        await prefs.setString('teacher_name', teacherName);
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_year');
        await prefs.remove('selected_semester');
        await prefs.remove('selected_section');
        await prefs.remove('student_gender');
        print('✅ Teacher data saved: $teacherName');
      } else if (role == 'admin') {
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_year');
        await prefs.remove('selected_semester');
        await prefs.remove('selected_section');
        await prefs.remove('student_gender');
        await prefs.remove('teacher_name');
        print('✅ Admin data saved');
      }

      // Also store subjects if available
      if (userData['subjects'] != null) {
        List<String> subjects = List<String>.from(userData['subjects']);
        await prefs.setStringList('selected_subjects', subjects);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });

      // Verify data was saved
      print('=== User Data Saved ===');
      print('user_role: ${prefs.getString('user_role')}');
      print('is_admin: ${prefs.getBool('is_admin')}');
      print('is_teacher: ${prefs.getBool('is_teacher')}');
      print('user_name: ${prefs.getString('user_name')}');
      print('student_name: ${prefs.getString('student_name')}');
      print('user_email: ${prefs.getString('user_email')}');
      print('========================');

      FCMService.showCustomNotification(
        title: 'Welcome Back! 👋',
        body: 'Good to see you again, $displayName!',
        context: context,
      );

      _showSuccessMessage('Welcome back $displayName!');
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        // Always navigate to home, HomePage will handle role-based display
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = 'No account found with this email/roll number';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email format';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email already in use';
      } else {
        message = 'Authentication failed: ${e.message}';
      }
      _showError(message);
    } catch (e) {
      _showError('An error occurred. Please try again.');
      print('Login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _parseSemesterNumber(dynamic semester) {
    if (semester == null) return 1;
    if (semester is int) return semester;
    if (semester is String) {
      final match = RegExp(r'\d+').firstMatch(semester);
      return match != null ? int.parse(match.group(0)!) : 1;
    }
    return 1;
  }

  Future<void> _guestLogin() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await prefs.setBool('has_logged_in', true);
      await prefs.setString('user_name', 'Guest');
      await prefs.setString('student_name', 'Guest');
      await prefs.setString('user_gender', 'Other');
      await prefs.setBool('is_guest', true);
      await prefs.setBool('is_admin', false);
      await prefs.setBool('is_teacher', false);
      await prefs.setString('user_role', 'guest');

      FCMService.showCustomNotification(
        title: 'Guest Mode 👤',
        body: 'You are browsing as a guest. Sign up for full access!',
        context: context,
      );
      _showSuccessMessage('Welcome Guest!');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      _showError('Guest login failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessMessage(String message) {
    setState(() {
      _successMessage = message;
      _showSuccess = true;
    });
    _successTimer?.cancel();
    _successTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _navigateToSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignupPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667EEA).withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: SvgPicture.asset(
                        'assets/logo/app_logo.svg',
                        colorFilter: const ColorFilter.mode(
                            Colors.white, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Campus Clock',
                    style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Shyam Lal College',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 50),
                  _buildTextField(
                    controller: _identifierController,
                    label: 'Email / Roll Number / Admin',
                    icon: Icons.person,
                    hintText: 'Enter email, roll number, or "Admin"',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email, roll number, or Admin is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.grey),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Password is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  _buildSubmitButton(onPressed: _loading ? null : _login),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading ? null : _guestLogin,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline,
                            color: Colors.white.withOpacity(0.8)),
                        const SizedBox(width: 8),
                        Text(
                          'Continue as Guest',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.8),
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ",
                          style: TextStyle(color: Colors.white70)),
                      TextButton(
                        onPressed: _navigateToSignup,
                        child: const Text('Sign up',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: _showSuccess
            ? Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 60),
                          const SizedBox(height: 16),
                          Text(_successMessage,
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () =>
                                setState(() => _showSuccess = false),
                            child: const Text('Continue'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    String? hintText,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              spreadRadius: 2)
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: Colors.blue),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildSubmitButton({VoidCallback? onPressed}) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 5,
        ),
        child: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 24),
                  SizedBox(width: 12),
                  Text('Login to Continue',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}
