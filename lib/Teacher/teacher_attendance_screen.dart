import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_database.dart';
import 'AttendanceAnalysisScreen.dart';
import '../Service/fcm_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TeacherAttendanceScreen extends StatefulWidget {
  const TeacherAttendanceScreen({super.key});

  @override
  State<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  final AttendanceDatabase db = AttendanceDatabase.instance;
  List<Map<String, dynamic>> _students = [];
  List<String> _availableCourses = [];
  String? _selectedCourse;
  String? _selectedYear;
  String? _selectedSemester;
  String? _selectedSection;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _teacherName;
  Map<String, bool> _todayAttendance = {}; // Use student document ID as key

  // Firebase collections
  final CollectionReference _studentsCollection = FirebaseFirestore.instance.collection('students');
  final CollectionReference _attendanceCollection = FirebaseFirestore.instance.collection('attendance');
  final CollectionReference _coursesCollection = FirebaseFirestore.instance.collection('courses');

  static const List<String> _allYears = ['1 Year', '2 Year', '3 Year'];
  static const List<String> _allSemesters = ['Semester 1', 'Semester 2', 'Semester 3', 'Semester 4', 'Semester 5', 'Semester 6'];

  @override
  void initState() {
    super.initState();
    _loadTeacherName();
    _loadAvailableCourses();
  }

  Future<void> _loadTeacherName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _teacherName = prefs.getString('teacher_name') ?? prefs.getString('user_name') ?? 'Teacher';
    });
  }

  // Load available courses from Firestore
  Future<void> _loadAvailableCourses() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _studentsCollection.get();
      final courses = <String>{};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['course'] != null) {
          courses.add(data['course'].toString());
        }
      }
      setState(() {
        _availableCourses = courses.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading courses: $e');
      setState(() => _isLoading = false);
      _showSnackBar('Error loading courses', isError: true);
    }
  }

  // Load students based on selected course, year, semester, section
  Future<void> _loadStudents() async {
    if (_selectedCourse == null) return;

    setState(() => _isLoading = true);
    try {
      Query query = _studentsCollection.where('course', isEqualTo: _selectedCourse);

      if (_selectedYear != null && _selectedYear!.isNotEmpty) {
        query = query.where('year', isEqualTo: _selectedYear);
      }
      if (_selectedSemester != null && _selectedSemester!.isNotEmpty) {
        query = query.where('semester', isEqualTo: _selectedSemester);
      }
      if (_selectedSection != null && _selectedSection!.isNotEmpty) {
        query = query.where('section', isEqualTo: _selectedSection);
      }

      final snapshot = await query.get();

      setState(() {
        _students = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Unknown',
            'rollNo': data['rollNo'] ?? 'N/A',
            'course': data['course'] ?? _selectedCourse,
            'year': data['year'] ?? _selectedYear,
            'semester': data['semester'] ?? _selectedSemester,
            'section': data['section'] ?? _selectedSection,
          };
        }).toList();
        _isLoading = false;
      });

      await _loadTodayAttendance();
    } catch (e) {
      print('Error loading students: $e');
      setState(() => _isLoading = false);
      _showSnackBar('Error loading students', isError: true);
    }
  }

  // Load today's attendance from Firestore
  Future<void> _loadTodayAttendance() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final attendanceMap = <String, bool>{};

    for (var student in _students) {
      final studentId = student['id'];
      final attendanceDoc = await _attendanceCollection
          .doc('${studentId}_$today')
          .get();

      if (attendanceDoc.exists) {
        final data = attendanceDoc.data() as Map<String, dynamic>;
        attendanceMap[studentId] = data['status'] == 1;
      } else {
        attendanceMap[studentId] = false;
      }
    }

    setState(() => _todayAttendance = attendanceMap);
  }

  // Toggle attendance in Firestore
  Future<void> _toggleAttendance(String studentId, bool value) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final attendanceId = '${studentId}_$today';

    try {
      await _attendanceCollection.doc(attendanceId).set({
        'studentId': studentId,
        'date': today,
        'status': value ? 1 : 0,
        'markedBy': _teacherName,
        'markedAt': FieldValue.serverTimestamp(),
        'course': _selectedCourse,
      });

      setState(() {
        _todayAttendance[studentId] = value;
      });

      _showSnackBar(value ? 'Marked present' : 'Marked absent');

      // Send notification to student
      await _sendAttendanceNotification(studentId, value);
    } catch (e) {
      print('Error marking attendance: $e');
      _showSnackBar('Error marking attendance', isError: true);
    }
  }

  // Send notification to student
  Future<void> _sendAttendanceNotification(String studentId, bool present) async {
    try {
      final student = _students.firstWhere((s) => s['id'] == studentId);
      final rollNumber = student['rollNo'].toString();

      // Get student's Firebase Auth user ID by roll number
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('rollNumber', isEqualTo: rollNumber)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        final studentUserId = userQuery.docs.first.id;
        // Remove the 'context' parameter - it's not needed
        await FCMService.sendNotificationToUser(
          userId: studentUserId,
          title: 'Attendance Marked',
          body: present
              ? '✓ You have been marked PRESENT for ${DateFormat('dd MMM yyyy').format(DateTime.now())}'
              : '✗ You have been marked ABSENT for ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
          senderName: _teacherName!,
          additionalData: {'course': _selectedCourse, 'rollNumber': rollNumber},
        );
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  // Show class selector with filters
  void _showClassSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        String? tempCourse = _selectedCourse;
        String? tempYear = _selectedYear;
        String? tempSemester = _selectedSemester;
        String? tempSection = _selectedSection;

        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Class', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // Course Dropdown
                  const Text('Course', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Select Course'),
                        value: tempCourse,
                        items: _availableCourses.map((course) {
                          return DropdownMenuItem(value: course, child: Text(course));
                        }).toList(),
                        onChanged: (value) => setStateModal(() => tempCourse = value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Year Dropdown
                  const Text('Year (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Select Year'),
                        value: tempYear,
                        items: _allYears.map((year) {
                          return DropdownMenuItem(value: year, child: Text(year));
                        }).toList(),
                        onChanged: (value) => setStateModal(() => tempYear = value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Semester Dropdown
                  const Text('Semester (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Select Semester'),
                        value: tempSemester,
                        items: _allSemesters.map((semester) {
                          return DropdownMenuItem(value: semester, child: Text(semester));
                        }).toList(),
                        onChanged: (value) => setStateModal(() => tempSemester = value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section Dropdown (get unique sections from Firestore)
                  const Text('Section (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FutureBuilder<List<String>>(
                    future: _getAvailableSections(tempCourse),
                    builder: (context, snapshot) {
                      final sections = snapshot.data ?? [];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text('Select Section'),
                            value: tempSection,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Sections')),
                              ...sections.map((section) {
                                return DropdownMenuItem(value: section, child: Text(section));
                              }),
                            ],
                            onChanged: (value) => setStateModal(() => tempSection = value),
                          ),
                        ),
                      );
                    },
                  ),

                  const Spacer(),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedCourse = tempCourse;
                              _selectedYear = tempYear;
                              _selectedSemester = tempSemester;
                              _selectedSection = tempSection;
                            });
                            Navigator.pop(context);
                            _loadStudents();
                          },
                          child: const Text('Load Students'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Get unique sections for a course
  Future<List<String>> _getAvailableSections(String? course) async {
    if (course == null) return [];
    try {
      final snapshot = await _studentsCollection.where('course', isEqualTo: course).get();
      final sections = <String>{};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['section'] != null) {
          sections.add(data['section'].toString());
        }
      }
      return sections.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  // Get attendance status for a specific date
  Future<int?> _getAttendanceStatus(String studentId, String date) async {
    final doc = await _attendanceCollection.doc('${studentId}_$date').get();
    if (doc.exists) {
      return (doc.data() as Map<String, dynamic>)['status'];
    }
    return null;
  }

  // Mark attendance for a specific date (for history)
  Future<void> _markAttendanceForDate() async {
    if (_selectedCourse == null || _students.isEmpty) return;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (selectedDate == null) return;

    setState(() => _selectedDate = selectedDate);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final attendanceStatus = <String, int?>{};

    for (var student in _students) {
      final status = await _getAttendanceStatus(student['id'], dateKey);
      attendanceStatus[student['id']] = status;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(16),
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    Text('Mark Attendance for ${DateFormat('dd MMM yyyy').format(_selectedDate)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _students.length,
                        itemBuilder: (ctx, index) {
                          final student = _students[index];
                          final currentStatus = attendanceStatus[student['id']] ?? 0;
                          return Card(
                            child: ListTile(
                              title: Text(student['name']),
                              subtitle: Text('Roll: ${student['rollNo']}'),
                              trailing: DropdownButton<int>(
                                value: currentStatus,
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('Absent')),
                                  DropdownMenuItem(value: 1, child: Text('Present')),
                                ],
                                onChanged: (val) async {
                                  if (val != null) {
                                    await _attendanceCollection.doc('${student['id']}_$dateKey').set({
                                      'studentId': student['id'],
                                      'date': dateKey,
                                      'status': val,
                                      'markedBy': _teacherName,
                                      'markedAt': FieldValue.serverTimestamp(),
                                      'course': _selectedCourse,
                                    });
                                    attendanceStatus[student['id']] = val;
                                    setStateModal(() {});
                                    if (dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now())) {
                                      await _loadTodayAttendance();
                                    }
                                    if (val == 1) await _sendAttendanceNotification(student['id'], true);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // QR Scanning
  Future<void> _scanQRAndMarkAttendance() async {
    if (_selectedCourse == null) {
      _showSnackBar('Please select a class first', isError: true);
      return;
    }

    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerDialog()));
    if (result == null) return;

    try {
      final data = jsonDecode(result) as Map<String, dynamic>;
      final rollNumber = data['rollNumber'] as String?;
      final course = data['course'] as String?;
      final qrDate = data['date'] as String?;

      if (rollNumber == null || course == null || qrDate == null) {
        _showSnackBar('Invalid QR code', isError: true);
        return;
      }

      if (course != _selectedCourse) {
        _showSnackBar('Student not in selected class', isError: true);
        return;
      }

      // Find student in current list
      Map<String, dynamic>? student;
      try {
        student = _students.firstWhere((s) => s['rollNo'] == rollNumber);
      } catch (_) {}

      if (student == null) {
        _showSnackBar('Roll number not found in this class', isError: true);
        return;
      }

      final existingStatus = await _getAttendanceStatus(student['id'], qrDate);
      if (existingStatus == 1) {
        _showSnackBar('${student['name']} already present for $qrDate');
        return;
      }

      await _attendanceCollection.doc('${student['id']}_$qrDate').set({
        'studentId': student['id'],
        'date': qrDate,
        'status': 1,
        'markedBy': _teacherName,
        'markedAt': FieldValue.serverTimestamp(),
        'course': _selectedCourse,
        'markedVia': 'QR',
      });

      _showSnackBar('✓ ${student['name']} marked present for $qrDate');
      await _sendAttendanceNotification(student['id'], true);

      if (qrDate == DateFormat('yyyy-MM-dd').format(DateTime.now())) {
        await _loadTodayAttendance();
      }
    } catch (e) {
      _showSnackBar('Error processing QR', isError: true);
    }
  }

  // Export report
  Future<void> _exportFilteredReport() async {
    if (_selectedCourse == null) return;

    final startDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (startDate == null) return;

    final endDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: startDate,
      lastDate: DateTime(2030),
    );
    if (endDate == null) return;

    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);

    // Get attendance data from Firestore
    final attendanceSnapshot = await _attendanceCollection
        .where('course', isEqualTo: _selectedCourse)
        .get();

    final filteredAttendance = attendanceSnapshot.docs
        .where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final date = data['date'] as String;
      return date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0;
    })
        .toList();

    if (filteredAttendance.isEmpty) {
      _showSnackBar('No data found', isError: true);
      return;
    }

    // Create CSV
    final buffer = StringBuffer();
    buffer.writeln('"Campus Clock - Attendance Report"');
    buffer.writeln('"Course","${_selectedCourse!.replaceAll('"', '""')}"');
    if (_selectedYear != null) buffer.writeln('"Year","${_selectedYear}"');
    if (_selectedSemester != null) buffer.writeln('"Semester","${_selectedSemester}"');
    if (_selectedSection != null) buffer.writeln('"Section","${_selectedSection}"');
    buffer.writeln('"Teacher","${_teacherName!.replaceAll('"', '""')}"');
    buffer.writeln('"Period","${DateFormat('dd MMM yyyy').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}"');
    buffer.writeln('"Generated on","${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}"');
    buffer.writeln();
    buffer.writeln('"Student Name","Roll Number","Date","Status"');

    for (var attendance in filteredAttendance) {
      final data = attendance.data() as Map<String, dynamic>;
      final studentId = data['studentId'];
      final studentDoc = await _studentsCollection.doc(studentId).get();
      final studentData = studentDoc.data() as Map<String, dynamic>;

      buffer.writeln('"${studentData['name']}","${studentData['rollNo']}","${data['date']}","${data['status'] == 1 ? 'Present' : 'Absent'}"');
    }

    final file = File('${Directory.systemTemp.path}/attendance_${_selectedCourse!.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report - $_selectedCourse');
  }

  // Print report
  Future<void> _printFilteredReport() async {
    if (_selectedCourse == null) return;

    final startDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (startDate == null) return;

    final endDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: startDate,
      lastDate: DateTime(2030),
    );
    if (endDate == null) return;

    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);

    // Get attendance data from Firestore
    final attendanceSnapshot = await _attendanceCollection
        .where('course', isEqualTo: _selectedCourse)
        .get();

    final filteredAttendance = attendanceSnapshot.docs
        .where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final date = data['date'] as String;
      return date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0;
    })
        .toList();

    if (filteredAttendance.isEmpty) {
      _showSnackBar('No data', isError: true);
      return;
    }

    // Prepare data for PDF
    final reportData = <Map<String, dynamic>>[];
    for (var attendance in filteredAttendance) {
      final data = attendance.data() as Map<String, dynamic>;
      final studentId = data['studentId'];
      final studentDoc = await _studentsCollection.doc(studentId).get();
      final studentData = studentDoc.data() as Map<String, dynamic>;

      reportData.add({
        'name': studentData['name'],
        'rollNo': studentData['rollNo'],
        'date': data['date'],
        'status': data['status'] == 1 ? 'Present' : 'Absent',
      });
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Campus Clock - Attendance Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Course: $_selectedCourse', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                if (_selectedYear != null) pw.Text('Year: $_selectedYear', style: pw.TextStyle(fontSize: 12)),
                if (_selectedSemester != null) pw.Text('Semester: $_selectedSemester', style: pw.TextStyle(fontSize: 12)),
                if (_selectedSection != null) pw.Text('Section: $_selectedSection', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Teacher: $_teacherName', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Period: ${DateFormat('dd MMM yyyy').format(startDate)} to ${DateFormat('dd MMM yyyy').format(endDate)}', style: pw.TextStyle(fontSize: 12)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Student Name', 'Roll Number', 'Date', 'Status'],
            data: reportData.map<List<String>>((record) => [
              record['name'] as String,
              record['rollNo'] as String,
              record['date'] as String,
              record['status'] as String,
            ]).toList(),
            border: pw.TableBorder.all(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Campus Clock - Shyam Lal College', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'attendance_${_selectedCourse!.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // UI: Class info card with filters
  Widget _buildClassInfoCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.indigo.shade800]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.class_, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedCourse!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      if (_selectedYear != null || _selectedSemester != null || _selectedSection != null)
                        Text(
                          [_selectedYear, _selectedSemester, _selectedSection].where((f) => f != null).join(' | '),
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: _showClassSelector,
                  tooltip: 'Change filters',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [const Icon(Icons.person, color: Colors.white70, size: 20), const SizedBox(width: 8), Text('Teacher: $_teacherName', style: const TextStyle(color: Colors.white70))]),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.people, color: Colors.white70, size: 20), const SizedBox(width: 8), Text('Total Students: ${_students.length}', style: const TextStyle(color: Colors.white70))]),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.calendar_today, color: Colors.white70, size: 20), const SizedBox(width: 8), Text('Today: ${DateFormat('dd MMM yyyy').format(DateTime.now())}', style: const TextStyle(color: Colors.white70))]),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final isPresent = _todayAttendance[student['id']] ?? false;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: Colors.blue.shade100, child: Text((student['name'][0] ?? 'S').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Roll: ${student['rollNo']}', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  Text('Sec: ${student['section'] ?? 'N/A'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Switch(
              value: isPresent,
              onChanged: (value) => _toggleAttendance(student['id'], value),
              activeColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCourse == null ? 'Attendance Diary' : _selectedCourse!),
        actions: _selectedCourse != null
            ? [
          IconButton(onPressed: _exportFilteredReport, icon: const Icon(Icons.ios_share), tooltip: 'Export Excel'),
          IconButton(onPressed: _printFilteredReport, icon: const Icon(Icons.print), tooltip: 'Print Report'),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AttendanceAnalysisScreen(
                    course: _selectedCourse!,
                    teacherName: _teacherName!,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.analytics),
            tooltip: 'Attendance Analysis',
          ),
        ]
            : [],
      ),
      body: _selectedCourse == null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.class_, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Select a class to start', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showClassSelector,
              icon: const Icon(Icons.search),
              label: const Text('Select Class'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ],
        ),
      )
          : Column(
        children: [
          _buildClassInfoCard(),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(alignment: Alignment.centerLeft, child: Text('Student List', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                ? const Center(child: Text('No students found for selected filters.'))
                : ListView.builder(itemCount: _students.length, itemBuilder: (ctx, idx) => _buildStudentCard(_students[idx])),
          ),
        ],
      ),
      floatingActionButton: _selectedCourse != null
          ? Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(heroTag: 'scan', mini: true, child: const Icon(Icons.qr_code_scanner), onPressed: _scanQRAndMarkAttendance, tooltip: 'Scan QR'),
          const SizedBox(height: 16),
          FloatingActionButton(heroTag: 'attendance', mini: true, child: const Icon(Icons.history), onPressed: _markAttendanceForDate, tooltip: 'Mark Attendance (other date)'),
        ],
      )
          : null,
    );
  }
}

// QR Scanner Dialog (same as before)
class QRScannerDialog extends StatefulWidget {
  const QRScannerDialog({super.key});

  @override
  State<QRScannerDialog> createState() => _QRScannerDialogState();
}

class _QRScannerDialogState extends State<QRScannerDialog> with SingleTickerProviderStateMixin {
  final MobileScannerController controller = MobileScannerController();
  bool isScanning = true;
  bool isTorchOn = false;
  late AnimationController _scanAnimationController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _scanAnimationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cutoutSize = size.width * 0.7;
    final left = (size.width - cutoutSize) / 2;
    final top = (size.height - cutoutSize) / 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() => isTorchOn = !isTorchOn);
              controller.toggleTorch();
            },
          ),
          IconButton(icon: const Icon(Icons.cameraswitch), onPressed: () => controller.switchCamera()),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (!isScanning) return;
              for (final barcode in capture.barcodes) {
                final rawValue = barcode.rawValue;
                if (rawValue != null) {
                  setState(() => isScanning = false);
                  Navigator.pop(context, rawValue);
                  return;
                }
              }
            },
          ),
          CustomPaint(painter: ScannerOverlayPainter(cutoutRect: Rect.fromLTWH(left, top, cutoutSize, cutoutSize)), child: Container()),
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) => Positioned(
              left: left,
              top: top + (_scanAnimation.value * cutoutSize),
              child: Container(width: cutoutSize, height: 2, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.transparent, Colors.cyan, Colors.transparent]), boxShadow: [BoxShadow(color: Colors.cyan, blurRadius: 6)])),
            ),
          ),
          Positioned(left: left - 2, top: top - 2, child: _buildCorner(Alignment.topLeft)),
          Positioned(right: left - 2, top: top - 2, child: _buildCorner(Alignment.topRight)),
          Positioned(left: left - 2, bottom: top - 2, child: _buildCorner(Alignment.bottomLeft)),
          Positioned(right: left - 2, bottom: top - 2, child: _buildCorner(Alignment.bottomRight)),
          const Positioned(bottom: 80, left: 0, right: 0, child: Text('Place QR code inside the frame', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          top: alignment.y == -1 ? const BorderSide(color: Colors.cyan, width: 4) : BorderSide.none,
          left: alignment.x == -1 ? const BorderSide(color: Colors.cyan, width: 4) : BorderSide.none,
          right: alignment.x == 1 ? const BorderSide(color: Colors.cyan, width: 4) : BorderSide.none,
          bottom: alignment.y == 1 ? const BorderSide(color: Colors.cyan, width: 4) : BorderSide.none,
        ),
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final Rect cutoutRect;
  ScannerOverlayPainter({required this.cutoutRect});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.6);
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height))..addRect(cutoutRect);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}