import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../Animation/animated_background.dart';
import '../service/fcm_service.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart'; // Add this if you have it

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
  bool _rememberMe = false;

  bool _showSuccess = false;
  String _successMessage = '';
  Timer? _successTimer;

  // Move hardcoded credentials to a secure location (e.g., .env file)
  // For now, keeping them but consider using Firebase Admin SDK instead
  static const String adminUsername = 'Admin';
  static const String adminEmail = 'admin@campusclock.com';
  static const String adminPassword = '20170024656';

  @override
  void initState() {
    super.initState();
    _initializeFCM();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedEmail = prefs.getString('remembered_email');
    final rememberedPassword = prefs.getString('remembered_password');

    if (rememberedEmail != null && rememberedPassword != null) {
      setState(() {
        _identifierController.text = rememberedEmail;
        _passwordController.text = rememberedPassword;
        _rememberMe = true;
      });
    }
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

  // Improved email lookup with caching
  final Map<String, String> _emailCache = {};

  Future<String?> _getEmailFromRollNumber(String rollNumber) async {
    // Check cache first
    if (_emailCache.containsKey(rollNumber)) {
      return _emailCache[rollNumber];
    }

    try {
      // Query both collections in parallel for better performance
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .where('rollNumber', isEqualTo: rollNumber)
            .limit(1)
            .get(),
        FirebaseFirestore.instance
            .collection('students')
            .where('rollNo', isEqualTo: rollNumber)
            .limit(1)
            .get(),
      ]);

      String? email;

      // Check users collection first
      if (results[0].docs.isNotEmpty) {
        email = results[0].docs.first.data()['email'] as String?;
      }

      // If not found, check students collection
      if (email == null && results[1].docs.isNotEmpty) {
        final studentData = results[1].docs.first.data();
        if (studentData.containsKey('email') && studentData['email'] != null) {
          email = studentData['email'] as String;
        }
      }

      // Cache the result
      if (email != null) {
        _emailCache[rollNumber] = email;
      }

      return email;
    } catch (e) {
      print('Error finding email from roll number: $e');
      return null;
    }
  }

  // Extract admin login logic
  Future<bool> _handleAdminLogin(String identifier, String password) async {
    if ((identifier == adminUsername || identifier == adminEmail) &&
        password == adminPassword) {
      print('✅ Admin logged in');

      final prefs = await SharedPreferences.getInstance();

      // Clear previous session data
      await _clearUserSessionData(prefs);

      // Set admin session data
      await _setAdminSessionData(prefs);

      FCMService.showCustomNotification(
        title: 'Admin Login 👑',
        body: 'Welcome to Admin Dashboard!',
        context: context,
      );

      _showSuccessMessage('Welcome Admin!');
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/admin', (route) => false);
      }
      return true;
    }
    return false;
  }

  Future<void> _clearUserSessionData(SharedPreferences prefs) async {
    await prefs.remove('roll_number');
    await prefs.remove('selected_course');
    await prefs.remove('selected_semester');
    await prefs.remove('student_name');
    await prefs.remove('student_gender');
    await prefs.remove('teacher_name');
    await prefs.remove('user_id');
    await prefs.remove('profile_photo_url');
  }

  Future<void> _setAdminSessionData(SharedPreferences prefs) async {
    await prefs.setBool('has_logged_in', true);
    await prefs.setString('user_name', 'Admin');
    await prefs.setString('user_email', 'admin@campusclock.com');
    await prefs.setBool('is_admin', true);
    await prefs.setBool('is_teacher', false);
    await prefs.setString('user_role', 'admin');
  }

  // Improved identifier validation
  String? _validateIdentifier(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email, roll number, or Admin is required';
    }

    final trimmed = value.trim();

    // Check for admin
    if (trimmed == adminUsername || trimmed == adminEmail) {
      return null;
    }

    // Check if it's a valid email format
    if (RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(trimmed)) {
      return null;
    }

    // Check if it's a valid roll number (numeric, adjust length as needed)
    if (RegExp(r'^\d{6,12}$').hasMatch(trimmed)) {
      return null;
    }

    return 'Please enter a valid email, roll number (6-12 digits), or "Admin"';
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      String identifier = _identifierController.text.trim();
      String password = _passwordController.text.trim();

      // Check for admin login first
      if (await _handleAdminLogin(identifier, password)) {
        return;
      }

      // Validate identifier for non-admin users
      final identifierValidation = _validateIdentifier(identifier);
      if (identifierValidation != null) {
        _showError(identifierValidation);
        return;
      }

      // Determine login method
      String email;
      bool isEmailLogin = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(identifier);

      if (!isEmailLogin) {
        // Treat as roll number
        final foundEmail = await _getEmailFromRollNumber(identifier);
        if (foundEmail == null) {
          _showError('No account found with this roll number');
          return;
        }
        email = foundEmail;
      } else {
        email = identifier;
      }

      // Attempt Firebase authentication
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email,
            password: password,
          )
          .timeout(const Duration(seconds: 30)); // Add timeout

      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        _showError('User data not found. Please contact support.');
        return;
      }

      // Process user data and session
      await _processUserLogin(
          userCredential, userDoc.data() as Map<String, dynamic>, email);
    } on FirebaseAuthException catch (e) {
      _handleFirebaseAuthError(e);
    } on TimeoutException {
      _showError('Connection timeout. Please check your internet connection.');
    } catch (e) {
      _showError('An error occurred. Please try again.');
      print('Login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _processUserLogin(
    UserCredential userCredential,
    Map<String, dynamic> userData,
    String email,
  ) async {
    // Determine user role
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

    // Save login info if remember me is checked
    if (_rememberMe) {
      await prefs.setString('remembered_email', email);
      await prefs.setString(
          'remembered_password', _passwordController.text.trim());
    } else {
      await prefs.remove('remembered_email');
      await prefs.remove('remembered_password');
    }

    // Set basic user info
    await prefs.setBool('has_logged_in', true);
    await prefs.setString('user_email', email);
    await prefs.setString('user_name', displayName);
    await prefs.setString('user_gender', userData['gender'] ?? 'Other');
    await prefs.setBool('is_teacher', role == 'teacher');
    await prefs.setBool('is_admin', isAdmin);
    await prefs.remove('is_guest');
    await prefs.setString('user_id', userCredential.user!.uid);
    await prefs.setString(
        'profile_photo_url', userData['profilePhotoUrl'] ?? '');
    await prefs.setString('user_role', role);

    // Store role-specific data
    await _storeRoleSpecificData(prefs, role, userData, displayName);

    // Update last login timestamp
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userCredential.user!.uid)
        .update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });

    // Show welcome notification
    FCMService.showCustomNotification(
      title: 'Welcome Back! 👋',
      body: 'Good to see you again, $displayName!',
      context: context,
    );

    _showSuccessMessage('Welcome back $displayName!');
    await Future.delayed(const Duration(milliseconds: 1500));

    // Navigate based on role
    if (mounted) {
      if (isAdmin) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/admin', (route) => false);
      } else {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  }

  Future<void> _storeRoleSpecificData(
    SharedPreferences prefs,
    String role,
    Map<String, dynamic> userData,
    String displayName,
  ) async {
    if (role == 'student') {
      await prefs.setString('roll_number', userData['rollNumber'] ?? '');
      await prefs.setString('selected_course', userData['course'] ?? '');
      await prefs.setInt(
          'selected_semester', _parseSemesterNumber(userData['semester']));
      await prefs.setString('selected_year', userData['year'] ?? '');
      await prefs.setString('selected_section', userData['section'] ?? '');
      await prefs.setString('student_name', displayName);
      await prefs.setString('student_gender', userData['gender'] ?? '');
      await prefs.remove('teacher_name');
    } else if (role == 'teacher') {
      await prefs.setString(
          'teacher_name', userData['teacherName'] ?? displayName);
      await _clearStudentData(prefs);
    } else if (role == 'admin') {
      await _clearStudentData(prefs);
      await prefs.remove('teacher_name');
    }
  }

  Future<void> _clearStudentData(SharedPreferences prefs) async {
    await prefs.remove('roll_number');
    await prefs.remove('selected_course');
    await prefs.remove('selected_year');
    await prefs.remove('selected_semester');
    await prefs.remove('selected_section');
    await prefs.remove('student_name');
    await prefs.remove('student_gender');
  }

  void _handleFirebaseAuthError(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'user-not-found':
        message = 'No account found with this email/roll number';
        break;
      case 'wrong-password':
        message = 'Incorrect password';
        break;
      case 'invalid-email':
        message = 'Invalid email format';
        break;
      case 'user-disabled':
        message = 'This account has been disabled';
        break;
      case 'too-many-requests':
        message = 'Too many failed attempts. Please try again later';
        break;
      case 'network-request-failed':
        message = 'Network error. Please check your connection';
        break;
      default:
        message = 'Authentication failed: ${e.message}';
    }
    _showError(message);
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

      await _clearUserSessionData(prefs);

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
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  void _navigateToSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignupPage()),
    );
  }

  void _navigateToForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
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
                  _buildLogo(),
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
                    validator: _validateIdentifier,
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
                  const SizedBox(height: 8),
                  _buildRememberMeAndForgotPassword(),
                  const SizedBox(height: 30),
                  _buildSubmitButton(onPressed: _loading ? null : _login),
                  const SizedBox(height: 16),
                  _buildGuestLoginButton(),
                  const SizedBox(height: 20),
                  _buildSignupRow(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: _showSuccess ? _buildSuccessDialog() : null,
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
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
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }

  Widget _buildRememberMeAndForgotPassword() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Checkbox(
              value: _rememberMe,
              onChanged: (value) =>
                  setState(() => _rememberMe = value ?? false),
              activeColor: Colors.blue,
              checkColor: Colors.white,
            ),
            const Text('Remember me', style: TextStyle(color: Colors.white70)),
          ],
        ),
        TextButton(
          onPressed: _navigateToForgotPassword,
          child: const Text('Forgot Password?',
              style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildGuestLoginButton() {
    return TextButton(
      onPressed: _loading ? null : _guestLogin,
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, color: Colors.white.withOpacity(0.8)),
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
    );
  }

  Widget _buildSignupRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Don't have an account? ",
            style: TextStyle(color: Colors.white70)),
        TextButton(
          onPressed: _navigateToSignup,
          child: const Text('Sign up',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSuccessDialog() {
    return Container(
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
