import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:campus_clock_slc/Teacher/attendance_database.dart';

class AttendanceRecord {
  final String date;
  final bool status;

  AttendanceRecord({required this.date, required this.status});
}

class StudentAttendanceAnalyticsScreen extends StatefulWidget {
  final String rollNumber;
  final String studentName;

  const StudentAttendanceAnalyticsScreen({
    super.key,
    required this.rollNumber,
    required this.studentName,
  });

  @override
  State<StudentAttendanceAnalyticsScreen> createState() => _StudentAttendanceAnalyticsScreenState();
}

class _StudentAttendanceAnalyticsScreenState extends State<StudentAttendanceAnalyticsScreen> {
  final AttendanceDatabase db = AttendanceDatabase.instance;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 90));
  DateTime _endDate = DateTime.now();
  bool _isLoading = true;
  List<AttendanceRecord> _records = [];
  int _totalDays = 0;
  int _presentDays = 0;
  double _percentage = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate);
    final student = await db.getStudentByRollNumber(widget.rollNumber);
    if (student == null) {
      setState(() => _isLoading = false);
      return;
    }
    final allRecords = await db.getAttendanceByDateRange(startStr, endStr);
    final myRecords = allRecords.where((r) => r['rollNumber'] == widget.rollNumber).toList();
    final List<AttendanceRecord> parsed = [];
    for (var r in myRecords) {
      final statusValue = r['status'] as int?;
      parsed.add(AttendanceRecord(
        date: r['date'] as String,
        status: statusValue == 1,
      ));
    }
    _records = parsed;
    _totalDays = _records.length;
    _presentDays = _records.where((r) => r.status).length;
    _percentage = _totalDays > 0 ? (_presentDays / _totalDays) * 100 : 0;
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
        title: Text('My Attendance - ${widget.studentName}'),
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
          : _records.isEmpty
          ? const Center(child: Text('No attendance records for this period.'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Roll Number: ${widget.rollNumber}',
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
                        _buildStatCard('Total Days', _totalDays.toString(), Icons.calendar_today, Colors.blue),
                        _buildStatCard('Present', _presentDays.toString(), Icons.check_circle, Colors.green),
                        _buildStatCard(
                          'Percentage',
                          '${_percentage.toStringAsFixed(1)}%',
                          Icons.analytics,
                          _percentage >= 75 ? Colors.green : (_percentage >= 50 ? Colors.orange : Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _percentage / 100,
                      backgroundColor: Colors.grey[300],
                      color: _percentage >= 75 ? Colors.green : (_percentage >= 50 ? Colors.orange : Colors.red),
                      minHeight: 10,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _percentage >= 75
                          ? 'Excellent! Keep it up'
                          : (_percentage >= 50 ? 'Need improvement' : 'Low attendance, please attend regularly'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Monthly Trend',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text('${value.toInt()}%'),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final monthIndex = value.toInt();
                          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          if (monthIndex >= 0 && monthIndex < months.length) return Text(months[monthIndex]);
                          return const Text('');
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _getMonthlyData(),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Daily History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _records.length,
              itemBuilder: (ctx, idx) {
                final record = _records[idx];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      record.status ? Icons.check_circle : Icons.cancel,
                      color: record.status ? Colors.green : Colors.red,
                    ),
                    title: Text(DateFormat('dd MMM yyyy').format(DateTime.parse(record.date))),
                    trailing: Text(
                      record.status ? 'Present' : 'Absent',
                      style: TextStyle(color: record.status ? Colors.green : Colors.red),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  List<BarChartGroupData> _getMonthlyData() {
    final Map<int, List<AttendanceRecord>> monthlyMap = {};
    for (var record in _records) {
      final date = DateTime.parse(record.date);
      final month = date.month - 1; // 0‑based
      monthlyMap.putIfAbsent(month, () => []);
      monthlyMap[month]!.add(record);
    }
    return List.generate(12, (month) {
      final records = monthlyMap[month] ?? [];
      final total = records.length;
      final present = records.where((r) => r.status).length;
      final percentage = total > 0 ? (present / total) * 100 : 0;
      return BarChartGroupData(
        x: month,
        barRods: [
          BarChartRodData(
            toY: percentage.toDouble(),
            color: percentage >= 75 ? Colors.green : (percentage >= 50 ? Colors.orange : Colors.red),
            width: 20,
          )
        ],
      );
    });
  }
}
