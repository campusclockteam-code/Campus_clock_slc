// lib/widgets/text_paste_dialog.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TextPasteDialog extends StatefulWidget {
  final Function(Map<String, dynamic> studentData, String documentId) onStudentAdded;
  final Function(int count) onBatchComplete;

  const TextPasteDialog({
    super.key,
    required this.onStudentAdded,
    required this.onBatchComplete,
  });

  @override
  State<TextPasteDialog> createState() => _TextPasteDialogState();
}

class _TextPasteDialogState extends State<TextPasteDialog> {
  final TextEditingController _textController = TextEditingController();
  String _selectedCourse = '';
  String _selectedYear = '';
  String _selectedSemester = '';
  String _selectedSection = '';
  bool _isProcessing = false;
  int _processedCount = 0;

  // Updated Course list
  final List<String> _courses = [
    'B.A. Prog(Economics+ OSMP)',
    'B.A. Prog(Economics+ Pol.Sc)',
    'B.A. Prog(Eng.+ Eco.)',
    'B.A. Prog(Eng.+ Pol.Sc)',
    'B.A. Prog(Hindi+ History)',
    'B.A. Prog(History+ Pol.Sc)',
    'B.A.(H) Economics',
    'B.A.(H) English',
    'B.A.(H) Hindi',
    'B.A.(H) History',
    'B.A.(H) Pol.Science',
    'B.Com(Prog.)',
    'B.Com(Hons.)',
    'Chemisty(Hons.)',
    'Math(Hons.)',
    'B.Sc.Physical Science(Chemistry)',
    'B.Sc.Physical Science(Computer Science)',
    'B.Sc.Physical Science(Electronics)',
    'M.A(Hindi)',
  ];

  final List<String> _years = ['1 Year', '2 Year', '3 Year'];
  final List<String> _semesters = ['Semester 1', 'Semester 2', 'Semester 3', 'Semester 4', 'Semester 5', 'Semester 6'];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width > 600 ? 600 : double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.content_paste, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Paste Student List',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isProcessing
                  ? _buildProcessingView(isDarkMode)
                  : _buildPasteForm(isDarkMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteForm(bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Course Selection
          _buildLabel('Course *'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCourse.isNotEmpty ? _selectedCourse : null,
            hint: const Text('Select Course'),
            isExpanded: true,
            decoration: _buildInputDecoration(isDarkMode),
            items: _courses.map((course) {
              return DropdownMenuItem(
                value: course,
                child: Text(course, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedCourse = value!),
          ),
          const SizedBox(height: 16),

          // Year and Semester Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Year *'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedYear.isNotEmpty ? _selectedYear : null,
                      hint: const Text('Select Year'),
                      decoration: _buildInputDecoration(isDarkMode),
                      items: _years.map((year) {
                        return DropdownMenuItem(
                          value: year,
                          child: Text(year),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedYear = value!),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Semester *'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedSemester.isNotEmpty ? _selectedSemester : null,
                      hint: const Text('Select Semester'),
                      decoration: _buildInputDecoration(isDarkMode),
                      items: _semesters.map((semester) {
                        return DropdownMenuItem(
                          value: semester,
                          child: Text(semester),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedSemester = value!),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Section
          _buildLabel('Section *'),
          const SizedBox(height: 8),
          TextFormField(
            decoration: _buildInputDecoration(isDarkMode, hint: 'e.g., C, A, B'),
            onChanged: (value) => _selectedSection = value,
          ),
          const SizedBox(height: 20),

          // Format Help - Updated for new format
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).primaryColor,
                        size: 16
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Format Instructions:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste student data in this format:\n\n'
                      'Roll Number\tName\n'
                      '250033\tAVNEET KAUR SALUJA\n'
                      '250034\tPIYUSH GUPTA\n\n'
                      'OR Space-separated format:\n'
                      '250033 AVNEET KAUR SALUJA\n'
                      '250034 PIYUSH GUPTA\n\n'
                      '• Roll Number must be numeric\n'
                      '• Name can have multiple words\n'
                      '• Duplicate roll numbers will be skipped\n'
                      '• Headers will be automatically detected and skipped',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Text Area
          _buildLabel('Student List *'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextFormField(
              controller: _textController,
              maxLines: 15,
              decoration: const InputDecoration(
                hintText: 'Paste your student list here...\n\n'
                    'Example:\n'
                    '250033\tAVNEET KAUR SALUJA\n'
                    '250034\tPIYUSH GUPTA\n'
                    '250036\tDIVY GUPTA',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Preview section
          if (_textController.text.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview (${_getStudentCountFromText()} students detected)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getPreviewText(),
                    style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _validateAndProcess,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Add Students'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingView(bool isDarkMode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Processing Students...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Added: $_processedCount students',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  InputDecoration _buildInputDecoration(bool isDarkMode, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  int _getStudentCountFromText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return 0;

    final lines = text.split('\n');
    int count = 0;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Try to split by tab first, then by space
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else {
        parts = line.split(RegExp(r'\s+'));
      }

      if (parts.length >= 2) {
        // Check if first part is numeric (roll number)
        if (int.tryParse(parts[0]) != null) {
          count++;
        }
      }
    }

    return count;
  }

  String _getPreviewText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return '';

    final lines = text.split('\n');
    final previewLines = <String>[];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Try to split by tab first, then by space
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else {
        parts = line.split(RegExp(r'\s+'));
      }

      if (parts.length >= 2) {
        // Check if first part is numeric (roll number)
        if (int.tryParse(parts[0]) != null) {
          final rollNo = parts[0];
          final name = parts.sublist(1).join(' ');
          previewLines.add('$rollNo - $name');
          if (previewLines.length >= 3) break;
        }
      }
    }

    return previewLines.join('\n') + (previewLines.length < _getStudentCountFromText() ? '\n...' : '');
  }

  Future<void> _validateAndProcess() async {
    if (_selectedCourse.isEmpty) {
      _showError('Please select a course');
      return;
    }
    if (_selectedYear.isEmpty) {
      _showError('Please select a year');
      return;
    }
    if (_selectedSemester.isEmpty) {
      _showError('Please select a semester');
      return;
    }
    if (_selectedSection.isEmpty) {
      _showError('Please enter a section');
      return;
    }
    if (_textController.text.trim().isEmpty) {
      _showError('Please paste student data');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
    });

    await _processTextPaste();
  }

  // Generate document ID: student_{year}_{rollNo}_{timestamp}
  String _generateDocumentId(String year, String rollNo) {
    // Convert "1 Year" to "1st", "2 Year" to "2nd", "3 Year" to "3rd"
    String yearPrefix = year.replaceAll(' Year', '');
    String yearSuffix = '';
    if (yearPrefix == '1') yearSuffix = 'st';
    else if (yearPrefix == '2') yearSuffix = 'nd';
    else if (yearPrefix == '3') yearSuffix = 'rd';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'student_${yearPrefix}${yearSuffix}_${rollNo}_$timestamp';
  }

  Future<void> _processTextPaste() async {
    final lines = _textController.text.trim().split('\n');
    List<Map<String, dynamic>> students = [];
    Set<String> processedRollNumbers = {};

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Try to split by tab first, then by space
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else {
        parts = line.split(RegExp(r'\s+'));
      }

      // Skip if not enough parts
      if (parts.length < 2) continue;

      // Check if first part is numeric (roll number)
      final rollNo = parts[0].trim();
      if (int.tryParse(rollNo) == null) continue; // Skip non-numeric roll numbers

      // Skip headers like "Roll Number" or "Name"
      if (rollNo.toLowerCase().contains('roll') ||
          rollNo.toLowerCase().contains('number') ||
          rollNo.toLowerCase().contains('name')) {
        continue;
      }

      // Get name (everything after the roll number)
      final name = parts.sublist(1).join(' ').trim();
      if (name.isEmpty) continue;

      // Skip duplicate roll numbers in the same paste
      if (processedRollNumbers.contains(rollNo)) continue;
      processedRollNumbers.add(rollNo);

      students.add({
        'rollNo': rollNo,
        'name': name,
        'course': _selectedCourse,
        'year': _selectedYear,
        'semester': _selectedSemester,
        'section': _selectedSection,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (students.isEmpty) {
      setState(() {
        _isProcessing = false;
      });
      _showError('No valid student data found. Please check the format.\nExpected format: Roll Number Name');
      return;
    }

    // Add students one by one with custom document IDs
    int duplicateCount = 0;

    for (var student in students) {
      try {
        // Generate document ID: student_{year}_{rollNo}_{timestamp}
        String docId = _generateDocumentId(_selectedYear, student['rollNo']);

        // Check if student with same roll number already exists in the database
        final existingStudent = await FirebaseFirestore.instance
            .collection('students')
            .where('rollNo', isEqualTo: student['rollNo'])
            .get();

        if (existingStudent.docs.isNotEmpty) {
          print('Student with roll number ${student['rollNo']} already exists, skipping...');
          duplicateCount++;
          continue;
        }

        // Add to Firestore with custom document ID
        await FirebaseFirestore.instance
            .collection('students')
            .doc(docId)
            .set(student);

        setState(() {
          _processedCount++;
        });

        // Callback with student data and document ID
        widget.onStudentAdded(student, docId);

        // Small delay to prevent overwhelming
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print('Error adding student: $e');
      }
    }

    // Notify completion with detailed message
    if (duplicateCount > 0) {
      _showSnackBar('✅ Added ${_processedCount} students. ⚠️ $duplicateCount duplicates skipped.');
    } else {
      _showSnackBar('✅ Successfully added ${_processedCount} students');
    }

    widget.onBatchComplete(_processedCount);

    // Close dialog after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}