import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'attendance_database.dart';

class AttendanceAnalysisScreen extends StatefulWidget {
  final String course;
  final String teacherName;

  const AttendanceAnalysisScreen({
    super.key,
    required this.course,
    required this.teacherName,
  });

  @override
  State<AttendanceAnalysisScreen> createState() => _AttendanceAnalysisScreenState();
}

class _AttendanceAnalysisScreenState extends State<AttendanceAnalysisScreen> {
  final AttendanceDatabase db = AttendanceDatabase.instance;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isLoading = true;
  List<StudentAttendance> _studentAttendance = [];
  int _totalStudents = 0;
  int _totalPresentDays = 0;
  double _averageAttendance = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

    // Fetch attendance records for the course in date range
    final records = await db.getAttendanceByDateRange(startStr, endStr, course: widget.course);
    // Group by student
    final Map<int, StudentAttendance> studentMap = {};
    for (var record in records) {
      final id = record['id'] as int;
      final name = record['name'] as String;
      final roll = record['rollNumber'] as String;
      final status = record['status'] as int?;
      if (!studentMap.containsKey(id)) {
        studentMap[id] = StudentAttendance(id: id, name: name, rollNumber: roll, totalDays: 0, presentDays: 0);
      }
      if (status != null) {
        studentMap[id]!.totalDays++;
        if (status == 1) studentMap[id]!.presentDays++;
      }
    }
    _studentAttendance = studentMap.values.toList();
    _totalStudents = _studentAttendance.length;
    _totalPresentDays = _studentAttendance.fold(0, (sum, s) => sum + (s.presentDays ?? 0));
    int totalPossibleDays = 0;
for (var s in _studentAttendance) {
  totalPossibleDays += (s.totalDays ?? 0);
}
    _averageAttendance = totalPossibleDays > 0 ? (_totalPresentDays / totalPossibleDays) * 100 : 0;

    setState(() => _isLoading = false);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Analysis'),
        actions: [
          IconButton(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range),
            tooltip: 'Select Date Range',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _studentAttendance.isEmpty
          ? const Center(child: Text('No attendance records for this period.'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Cards
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Course: ${widget.course}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Period: ${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem('Students', _totalStudents.toString(), Icons.people),
                        _buildSummaryItem('Present Days', _totalPresentDays.toString(), Icons.check_circle, color: Colors.green),
                        _buildSummaryItem('Avg. Attendance', '${_averageAttendance.toStringAsFixed(1)}%', Icons.analytics, color: Colors.blue),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Student-wise Attendance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Bar Chart
            SizedBox(
              height: 400,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) {
                        return Text('${value.toInt()}%', style: const TextStyle(fontSize: 10));
                      }),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= _studentAttendance.length) return const Text('');
                          return RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              _studentAttendance[index].name.length > 8
                                  ? '${_studentAttendance[index].name.substring(0, 6)}..'
                                  : _studentAttendance[index].name,
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                        reservedSize: 60,
                      ),
                    ),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _studentAttendance.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final student = entry.value;
                    final percentage = student.totalDays > 0 ? (student.presentDays / student.totalDays) * 100 : 0;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: percentage.toDouble(),
                          color: percentage >= 75 ? Colors.green : (percentage >= 50 ? Colors.orange : Colors.red),
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Detailed List',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _studentAttendance.length,
              itemBuilder: (ctx, idx) {
                final s = _studentAttendance[idx];
                final percentage = s.totalDays > 0 ? (s.presentDays / s.totalDays) * 100 : 0;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: percentage >= 75 ? Colors.green.shade100 : (percentage >= 50 ? Colors.orange.shade100 : Colors.red.shade100),
                      child: Text('${(percentage).toInt()}%', style: const TextStyle(fontSize: 12)),
                    ),
                    title: Text(s.name),
                    subtitle: Text('Roll: ${s.rollNumber}'),
                    trailing: Text('${s.presentDays} / ${s.totalDays} days'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, {Color color = Colors.black}) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class StudentAttendance {
  final int id;
  final String name;
  final String rollNumber;
  int totalDays;
  int presentDays;

  StudentAttendance({
    required this.id,
    required this.name,
    required this.rollNumber,
    required this.totalDays,
    required this.presentDays,
  });
}
