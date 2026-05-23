import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../basic_feture/ProfileScreen.dart';
import 'package:campus_clock_slc/Student/StudentAttendanceAnalyticsScreen.dart'; // adjust path

class StudentQRCodeScreen extends StatefulWidget {
  const StudentQRCodeScreen({super.key});

  @override
  State<StudentQRCodeScreen> createState() => _StudentQRCodeScreenState();
}

class _StudentQRCodeScreenState extends State<StudentQRCodeScreen> {
  String _qrData = '';
  bool _isLoading = true;
  String? _studentName;
  String? _rollNumber;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('student_name') ?? prefs.getString('user_name');
    final roll = prefs.getString('roll_number');
    final course = prefs.getString('selected_course');

    if (name == null || name.isEmpty || roll == null || roll.isEmpty || course == null || course.isEmpty) {
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileScreen(isFirstTime: false)),
        );
        if (result == true) {
          await _loadStudentData();
        } else {
          if (mounted) Navigator.pop(context);
        }
      }
      return;
    }

    _studentName = name;
    _rollNumber = roll;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final payload = {
      'name': name,
      'rollNumber': roll,
      'course': course,
      'date': today,
    };

    setState(() {
      _qrData = jsonEncode(payload);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance QR Code')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text('Show this QR code to your teacher', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: QrImageView(data: _qrData, version: QrVersions.auto, size: 250, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 30),
            Text(
              'Date: ${_getDataField('date')}\nName: ${_getDataField('name')}\nRoll: ${_getDataField('rollNumber')}\nCourse: ${_getDataField('course')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_rollNumber != null && _studentName != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentAttendanceAnalyticsScreen(
                  rollNumber: _rollNumber!,
                  studentName: _studentName!,
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.analytics),
        label: const Text('My Attendance'),
      ),
    );
  }

  String _getDataField(String key) {
    if (_qrData.isEmpty) return '';
    try {
      final map = jsonDecode(_qrData);
      return map[key] ?? '';
    } catch (_) {
      return '';
    }
  }
}