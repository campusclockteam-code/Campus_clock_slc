import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatefulWidget {
  final bool isFirstTime;
  const ProfileScreen({super.key, this.isFirstTime = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // User data
  String? _rollNumber;
  String? _name;
  String? _email;
  String? _gender;
  String? _course;
  String? _year;
  String? _section;
  int? _semester;
  String? _avatarPath;
  String? _userId;
  bool _isStudent = false;
  bool _isTeacher = false;

  bool _isLoading = true;
  bool _isUpdatingGender = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;

      setState(() {
        _rollNumber = prefs.getString('roll_number');
        _name = prefs.getString('user_name');
        _email = prefs.getString('user_email') ?? user?.email;
        _gender = prefs.getString('user_gender');
        _course = prefs.getString('selected_course');
        _year = prefs.getString('selected_year');
        _section = prefs.getString('selected_section');
        _semester = prefs.getInt('selected_semester');
        _avatarPath = prefs.getString('profile_image_path');
        _userId = prefs.getString('user_id') ?? user?.uid;
        _isStudent = prefs.getBool('is_teacher') == false;
        _isTeacher = prefs.getBool('is_teacher') == true;
      });

      // If userId not in prefs, fetch it using email
      if (_userId == null && _email != null) {
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: _email)
            .limit(1)
            .get();
        if (userQuery.docs.isNotEmpty) {
          _userId = userQuery.docs.first.id;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', _userId!);
        }
      }

      // 🔥 NEW: Fetch complete student data from 'students' collection using roll number
      if (_rollNumber != null && _rollNumber!.isNotEmpty && _isStudent) {
        await _fetchStudentDataFromFirestore(_rollNumber!);
      }
    } catch (e) {
      print('Error loading user data: $e');
      _showError('Error loading profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🔥 NEW METHOD: Fetch student data from Firestore using roll number
  Future<void> _fetchStudentDataFromFirestore(String rollNumber) async {
    try {
      // Query the 'students' collection for the roll number
      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('rollNo', isEqualTo: rollNumber)
          .limit(1)
          .get();

      if (studentQuery.docs.isNotEmpty) {
        final studentData = studentQuery.docs.first.data();

        setState(() {
          // Update all student details from Firestore
          _name = studentData['name'] ?? _name;
          _course = studentData['course'] ?? _course;
          _year = studentData['year'] ?? _year;
          _section = studentData['section'] ?? _section;
          _semester = _parseSemesterNumber(studentData['semester']);
          _gender = studentData['gender'] ?? _gender;
          _rollNumber = studentData['rollNo'] ?? _rollNumber;
          _email = studentData['email'] ?? _email;
        });

        // Update SharedPreferences with fetched data
        final prefs = await SharedPreferences.getInstance();
        if (studentData['course'] != null) {
          await prefs.setString('selected_course', studentData['course']);
        }
        if (studentData['year'] != null) {
          await prefs.setString('selected_year', studentData['year']);
        }
        if (studentData['section'] != null) {
          await prefs.setString('selected_section', studentData['section']);
        }
        if (studentData['semester'] != null) {
          await prefs.setInt('selected_semester',
              _parseSemesterNumber(studentData['semester']));
        }
        if (studentData['name'] != null) {
          await prefs.setString('student_name', studentData['name']);
          await prefs.setString('user_name', studentData['name']);
        }
        if (studentData['gender'] != null) {
          await prefs.setString('student_gender', studentData['gender']);
          await prefs.setString('user_gender', studentData['gender']);
        }
        if (studentData['email'] != null) {
          await prefs.setString('user_email', studentData['email']);
        }

        print(
            '✅ Student data fetched from Firestore for roll number: $rollNumber');
      } else {
        print('⚠️ No student data found for roll number: $rollNumber');
      }
    } catch (e) {
      print('Error fetching student data: $e');
    }
  }

  int _parseSemesterNumber(dynamic semester) {
    if (semester == null) return 1;
    if (semester is int) return semester;
    final str = semester.toString();
    final match = RegExp(r'\d+').firstMatch(str);
    return match != null ? int.parse(match.group(0)!) : 1;
  }

  Future<void> _updateGender(String newGender) async {
    if (newGender == _gender) return;
    if (_userId == null) {
      _showError('User ID not found');
      return;
    }

    setState(() => _isUpdatingGender = true);
    try {
      // 1. Update Firestore 'users' collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({'gender': newGender});

      // 2. If student, also update 'students' collection using roll number
      if (_rollNumber != null && _rollNumber!.isNotEmpty && _isStudent) {
        final studentQuery = await FirebaseFirestore.instance
            .collection('students')
            .where('rollNo', isEqualTo: _rollNumber)
            .limit(1)
            .get();
        if (studentQuery.docs.isNotEmpty) {
          await studentQuery.docs.first.reference.update({'gender': newGender});
        }
      }

      // 3. Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_gender', newGender);
      if (_isStudent) {
        await prefs.setString('student_gender', newGender);
      }

      setState(() => _gender = newGender);
      _showSuccess('Gender updated successfully');
    } catch (e) {
      _showError('Failed to update gender: $e');
    } finally {
      setState(() => _isUpdatingGender = false);
    }
  }

  void _showGenderPicker() {
    final List<String> genders = ['Male', 'Female', 'Other'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Select Gender',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ...genders.map((gender) => ListTile(
                  leading: Icon(
                      _gender == gender
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: Colors.blue),
                  title: Text(gender),
                  onTap: () {
                    Navigator.pop(context);
                    _updateGender(gender);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  void _navigateToHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar:
          widget.isFirstTime ? null : AppBar(title: const Text('My Profile')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileHeader(),
            _buildProfileDetails(),
            const SizedBox(height: 40),
            _buildContinueButton(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade800, Colors.purple.shade600]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white.withOpacity(0.2),
            backgroundImage:
                _avatarPath != null && File(_avatarPath!).existsSync()
                    ? FileImage(File(_avatarPath!))
                    : null,
            child: (_avatarPath == null || !File(_avatarPath!).existsSync())
                ? Text(
                    _name?.isNotEmpty == true ? _name![0].toUpperCase() : 'U',
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white))
                : null,
          ),
          const SizedBox(height: 16),
          Text(_name ?? 'Student',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 4),
          if (_email != null)
            Text(_email!,
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withOpacity(0.8))),
          if (_rollNumber != null && _rollNumber!.isNotEmpty)
            Text('Roll No: $_rollNumber',
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withOpacity(0.8))),
          if (_isTeacher)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Teacher',
                  style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileDetails() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isStudent ? 'Student Information' : 'Teacher Information',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildInfoRow('Full Name', _name ?? 'Not provided', Icons.person),
          const SizedBox(height: 12),
          _buildInfoRow('Email', _email ?? 'Not provided', Icons.email),
          const SizedBox(height: 12),
          if (_isStudent) ...[
            _buildInfoRow('Roll Number', _rollNumber ?? 'Not set', Icons.badge),
            const SizedBox(height: 12),
          ],
          _buildEditableGenderRow(),
          if (_isStudent) ...[
            const SizedBox(height: 12),
            _buildInfoRow('Course', _course ?? 'Not selected', Icons.school),
            const SizedBox(height: 12),
            _buildInfoRow('Year', _year ?? 'Not set', Icons.calendar_today),
            const SizedBox(height: 12),
            _buildInfoRow(
                'Semester',
                _semester != null ? 'Semester $_semester' : 'Not set',
                Icons.numbers),
            const SizedBox(height: 12),
            _buildInfoRow('Section', _section ?? 'Not set', Icons.group),
          ],
        ],
      ),
    );
  }

  Widget _buildEditableGenderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        children: [
          const Icon(Icons.people, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gender',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Row(
                  children: [
                    Expanded(
                        child: Text(_gender ?? 'Not specified',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500))),
                    if (_isUpdatingGender)
                      const SizedBox(
                          width: 8,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      IconButton(
                          icon: const Icon(Icons.edit,
                              size: 18, color: Colors.blue),
                          onPressed: _showGenderPicker,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _navigateToHome,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          child: const Text('Continue to Dashboard',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
