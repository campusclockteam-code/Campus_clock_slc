import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../Animation/animated_background.dart';
import '../Service/fcm_service.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  // ---------- Role selection ----------
  String? _selectedRole;
  bool _roleSelected = false;

  // Common fields
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rollNumberController = TextEditingController();
  String? _selectedGender;
  final _nameController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _isValidatingRoll = false;

  final List<String> _genders = ['Male', 'Female', 'Other'];
  Map<String, dynamic>? _fetchedStudentData;

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
    _emailController.dispose();
    _passwordController.dispose();
    _rollNumberController.dispose();
    _nameController.dispose();
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _signOutExistingUser() async {
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _showRoleSelectionDialog() async {
    final role = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sign up as'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.school, color: Colors.blue),
              title: const Text('Student'),
              onTap: () => Navigator.pop(context, 'student'),
            ),
            ListTile(
              leading: Icon(Icons.assignment_ind, color: Colors.green),
              title: const Text('Teacher'),
              onTap: () => Navigator.pop(context, 'teacher'),
            ),
            ListTile(
              leading: Icon(Icons.person_outline, color: Colors.orange),
              title: const Text('Other'),
              onTap: () => Navigator.pop(context, 'other'),
            ),
          ],
        ),
      ),
    );
    if (role != null) {
      setState(() {
        _selectedRole = role;
        _roleSelected = true;
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<Map<String, dynamic>?> _validateAndFetchStudent(String rollNumber) async {
    if (rollNumber.isEmpty) {
      setState(() => _fetchedStudentData = null);
      return null;
    }
    setState(() => _isValidatingRoll = true);
    try {
      final rollDoc = await FirebaseFirestore.instance
          .collection('student_rolls')
          .doc(rollNumber)
          .get();

      if (!rollDoc.exists) {
        setState(() => _fetchedStudentData = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid roll number. Contact admin.'), backgroundColor: Colors.orange),
        );
        return null;
      }

      final data = rollDoc.data() as Map<String, dynamic>;

      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('rollNo', isEqualTo: rollNumber)
          .limit(1)
          .get();

      if (studentSnapshot.docs.isNotEmpty) {
        final studentData = studentSnapshot.docs.first.data() as Map<String, dynamic>;
        if (studentData.containsKey('userId') && studentData['userId'] != null) {
          setState(() => _fetchedStudentData = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This roll number is already registered.'), backgroundColor: Colors.red),
          );
          return null;
        }
      }

      setState(() => _fetchedStudentData = data);
      return data;
    } catch (e) {
      setState(() => _fetchedStudentData = null);
      print('Error fetching student: $e');
      return null;
    } finally {
      setState(() => _isValidatingRoll = false);
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGender == null) {
      _showError('Please select gender');
      return;
    }

    setState(() => _loading = true);
    try {
      await _signOutExistingUser();

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      String name = '';
      Map<String, dynamic>? studentData;

      if (_selectedRole == 'student') {
        final rollNumber = _rollNumberController.text.trim();
        if (rollNumber.isEmpty) {
          _showError('Roll number required');
          return;
        }

        final rollDoc = await FirebaseFirestore.instance
            .collection('student_rolls')
            .doc(rollNumber)
            .get();

        if (!rollDoc.exists) {
          _showError('Invalid roll number. Please contact admin.');
          return;
        }

        studentData = rollDoc.data() as Map<String, dynamic>;

        final existingStudent = await FirebaseFirestore.instance
            .collection('students')
            .where('rollNo', isEqualTo: rollNumber)
            .limit(1)
            .get();

        if (existingStudent.docs.isNotEmpty) {
          final existingData = existingStudent.docs.first.data() as Map<String, dynamic>;
          if (existingData.containsKey('userId') && existingData['userId'] != null) {
            _showError('This roll number is already registered.');
            return;
          }
        }

        name = studentData['name'] ?? '';
      } else {
        name = _nameController.text.trim();
        if (name.isEmpty) {
          _showError('Name required');
          return;
        }
      }

      final UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final userId = userCredential.user!.uid;

      final Map<String, dynamic> userData = {
        'displayName': name,
        'email': email,
        'gender': _selectedGender,
        'role': _selectedRole,
        'isAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'profilePhotoUrl': '',
      };

      if (_selectedRole == 'student') {
        final rollNumber = _rollNumberController.text.trim();
        userData['rollNumber'] = rollNumber;
        userData['course'] = studentData!['course'] ?? '';
        userData['year'] = studentData['year'] ?? '';
        userData['semester'] = studentData['semester'] ?? '';
        userData['section'] = studentData['section'] ?? '';

        final studentId = 'student_${rollNumber}_${DateTime.now().millisecondsSinceEpoch}';
        await FirebaseFirestore.instance.collection('students').doc(studentId).set({
          'rollNo': rollNumber,
          'name': name,
          'email': email,
          'userId': userId,
          'course': studentData['course'] ?? '',
          'year': studentData['year'] ?? '',
          'semester': studentData['semester'] ?? '',
          'section': studentData['section'] ?? '',
          'gender': _selectedGender,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (_selectedRole == 'teacher') {
        userData['teacherName'] = name;
        userData['department'] = '';
      } else {
        userData['otherType'] = true;
      }

      await FirebaseFirestore.instance.collection('users').doc(userId).set(userData);

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_logged_in', true);
      await prefs.setString('user_email', email);
      await prefs.setString('user_name', name);
      await prefs.setString('user_gender', _selectedGender!);
      await prefs.setBool('is_teacher', _selectedRole == 'teacher');
      await prefs.setBool('is_admin', false);
      await prefs.remove('is_guest');
      await prefs.setString('profile_photo_url', '');
      await prefs.setString('user_id', userId);

      if (_selectedRole == 'student') {
        final rollNumber = _rollNumberController.text.trim();
        await prefs.setString('roll_number', rollNumber);
        await prefs.setString('selected_course', studentData!['course'] ?? '');
        await prefs.setString('selected_year', studentData['year'] ?? '');
        await prefs.setInt('selected_semester', _parseSemesterNumber(studentData['semester']));
        await prefs.setString('selected_section', studentData['section'] ?? '');
        await prefs.setString('student_name', name);
        await prefs.setString('student_gender', _selectedGender!);
        await prefs.remove('teacher_name');
      } else if (_selectedRole == 'teacher') {
        await prefs.setString('teacher_name', name);
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_year');
        await prefs.remove('selected_semester');
        await prefs.remove('selected_section');
        await prefs.remove('student_name');
        await prefs.remove('student_gender');
      } else {
        await prefs.remove('roll_number');
        await prefs.remove('selected_course');
        await prefs.remove('selected_year');
        await prefs.remove('selected_semester');
        await prefs.remove('selected_section');
        await prefs.remove('student_name');
        await prefs.remove('student_gender');
        await prefs.remove('teacher_name');
      }

      // ðŸŽ‰ Show success notification
      FCMService.showCustomNotification(
        title: 'Welcome to Campus Clock! ðŸŽ‰',
        body: 'Your account has been created successfully, $name!',
        context: context,
      );

      _showSuccessMessage('Account created successfully!');
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'email-already-in-use') {
        message = 'Email already registered';
      } else if (e.code == 'weak-password') {
        message = 'Password too weak (min 6 characters)';
      } else if (e.code == 'network-request-failed') {
        message = 'Network error. Check your connection.';
      } else {
        message = 'Signup failed: ${e.message}';
      }
      _showError(message);
    } catch (e) {
      _showError('An error occurred: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _parseSemesterNumber(dynamic semester) {
    if (semester == null) return 1;
    if (semester is int) return semester;
    final str = semester.toString();
    final match = RegExp(r'\d+').firstMatch(str);
    return match != null ? int.parse(match.group(0)!) : 1;
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
      SnackBar(content: Text(message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRoleSelectionDialog());
    }

    return AnimatedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _roleSelected
              ? SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  // SVG Logo instead of container with icon
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SvgPicture.asset(
                        'assets/logo/app_logo.svg',
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '${_selectedRole!.toUpperCase()} Sign Up',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  if (_selectedRole == 'student') ...[
                    _buildTextField(
                      controller: _rollNumberController,
                      label: 'Roll Number',
                      icon: Icons.numbers,
                      onChanged: (value) => _validateAndFetchStudent(value.trim()),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Roll number required';
                        if (int.tryParse(v.trim()) == null) return 'Must be numeric';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_isValidatingRoll)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_fetchedStudentData != null && !_isValidatingRoll)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('âœ“ Roll number verified', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            const SizedBox(height: 4),
                            Text('Name: ${_fetchedStudentData!['name'] ?? 'N/A'}'),
                            Text('Course: ${_fetchedStudentData!['course'] ?? 'N/A'}'),
                            Text('Year: ${_fetchedStudentData!['year'] ?? 'N/A'}'),
                            Text('Section: ${_fetchedStudentData!['section'] ?? 'N/A'}'),
                          ],
                        ),
                      ),
                  ],

                  if (_selectedRole != 'student') ...[
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name required' : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email required';
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password required';
                      if (v.length < 6) return 'Minimum 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildGenderSelector(),
                  const SizedBox(height: 30),

                  _buildSubmitButton(onPressed: _loading ? null : _signup),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? ', style: TextStyle(color: Colors.white70)),
                      TextButton(
                        onPressed: _navigateToLogin,
                        child: const Text('Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          )
              : const Center(child: CircularProgressIndicator()),
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
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, spreadRadius: 2)],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        onChanged: onChanged,
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

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Gender', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: _genders.map((gender) {
            final isSelected = _selectedGender == gender;
            return FilterChip(
              label: Text(gender),
              selected: isSelected,
              onSelected: (selected) => setState(() => _selectedGender = selected ? gender : null),
              selectedColor: Colors.blue.shade100,
              backgroundColor: Colors.white.withOpacity(0.2),
              labelStyle: TextStyle(color: isSelected ? Colors.blue.shade800 : Colors.white),
            );
          }).toList(),
        ),
      ],
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
            Icon(Icons.person_add, size: 24),
            SizedBox(width: 12),
            Text('Create Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}