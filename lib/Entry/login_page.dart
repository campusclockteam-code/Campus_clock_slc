import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../Animation/animated_background.dart';
import '../Service/fcm_service.dart';
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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      String identifier = _identifierController.text.trim();
      String password = _passwordController.text.trim();

      String email;

      if (int.tryParse(identifier) != null) {
        final foundEmail = await _getEmailFromRollNumber(identifier);
        if (foundEmail == null) {
          _showError('No account found with this roll number');
          return;
        }
        email = foundEmail;
      } else {
        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(identifier)) {
          _showError('Enter a valid email or numeric roll number');
          return;
        }
        email = identifier;
      }

      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
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

      // âœ… FIX: Check admin FIRST - it overrides everything
      bool isAdmin = userData['isAdmin'] == true ||
          email.toLowerCase() == 'surajncc2006@gmail.com';

      String role = 'student'; // default role

      if (isAdmin) {
        role = 'admin';  // Admin is separate role
      } else {
        role = userData['role'] ?? 'student';
      }

      String displayName = userData['displayName'] ?? (userData['teacherName'] ?? userData['studentName'] ?? 'User');

      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('has_logged_in', true);
      await prefs.setString('user_email', email);
      await prefs.setString('user_name', displayName);
      await prefs.setString('user_gender', userData['gender'] ?? 'Other');
      await prefs.setBool('is_teacher', role == 'teacher');
      await prefs.setBool('is_admin', isAdmin);
      await prefs.remove('is_guest');
      await prefs.setString('user_id', userCredential.user!.uid);
      await prefs.setString('profile_photo_url', userData['profilePhotoUrl'] ?? '');
      await prefs.setString('user_role', role);  // Store role: 'admin', 'teacher', or 'student'

      // Store role-specific data
      if (role == 'student') {
        await prefs.setString('roll_number', userData['rollNumber'] ?? '');
        await prefs.setString('selected_course', userData['course'] ?? '');
        await prefs.setInt('selected_semester', _parseSemesterNumber(userData['semester']));
        await prefs.setString('selected_year', userData['year'] ?? '');
        await prefs.setString('selected_section', userData['section'] ?? '');
        await prefs.setString('student_name', displayName);
        await prefs.setString('student_gender', userData['gender'] ?? '');
        await prefs.remove('teacher_name');
      } else if (role == 'teacher') {
        await prefs.setString('teacher_name', userData['teacherName'] ?? displayName);
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_year');
        await prefs.remove('selected_semester');
        await prefs.remove('selected_section');
        await prefs.remove('student_name');
        await prefs.remove('student_gender');
      } else if (role == 'admin') {
        // Admin doesn't need any student/teacher fields
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_year');
        await prefs.remove('selected_semester');
        await prefs.remove('selected_section');
        await prefs.remove('student_name');
        await prefs.remove('student_gender');
        await prefs.remove('teacher_name');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });

      // Show welcome back notification
      FCMService.showCustomNotification(
        title: 'Welcome Back! ðŸ‘‹',
        body: 'Good to see you again, $displayName!',
        context: context,
      );

      _showSuccessMessage('Welcome back $displayName!');
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        // âœ… Navigate based on role
        if (isAdmin) {
          Navigator.of(context).pushNamedAndRemoveUntil('/admin', (route) => false);
        } else {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        }
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
      await prefs.setBool('has_logged_in', true);
      await prefs.setString('user_name', 'Guest');
      await prefs.setString('user_gender', 'Other');
      await prefs.setBool('is_guest', true);
      await prefs.setBool('is_admin', false);
      await prefs.setBool('is_teacher', false);
      await prefs.setString('user_role', 'guest');
      await prefs.remove('roll_number');
      await prefs.remove('selected_course');
      await prefs.remove('selected_semester');
      await prefs.remove('student_name');
      await prefs.remove('student_gender');
      await prefs.remove('teacher_name');
      await prefs.remove('user_id');
      await prefs.remove('profile_photo_url');

      FCMService.showCustomNotification(
        title: 'Guest Mode ðŸ‘¤',
        body: 'You are browsing as a guest. Sign up for full access!',
        context: context,
      );

      _showSuccessMessage('Welcome Guest!');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
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
                        gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
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
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Campus Clock',
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white),
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
                    label: 'Email or Roll Number',
                    icon: Icons.person,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Email or roll number is required';
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
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Password is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  _buildSubmitButton(onPressed: _loading ? null : _login),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading ? null : _guestLogin,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline, color: Colors.white.withOpacity(0.8)),
                        const SizedBox(width: 8),
                        Text(
                          'Continue as Guest',
                          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
                      TextButton(
                        onPressed: _navigateToSignup,
                        child: const Text('Sign up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    const Icon(Icons.check_circle, color: Colors.green, size: 60),
                    const SizedBox(height: 16),
                    Text(_successMessage, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => _showSuccess = false),
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
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, spreadRadius: 2)],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 5,
        ),
        child: _loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login, size: 24),
            SizedBox(width: 12),
            Text('Login to Continue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}