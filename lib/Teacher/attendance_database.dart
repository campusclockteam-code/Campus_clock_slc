import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'dart:io';

class AttendanceDatabase {
  static final AttendanceDatabase instance = AttendanceDatabase._init();
  static Database? _database;

  AttendanceDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('attendance.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, fileName);
    return await openDatabase(path, version: 4, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        rollNumber TEXT NOT NULL UNIQUE,
        course TEXT NOT NULL,
        year INTEGER NOT NULL,
        semester INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        date TEXT NOT NULL,
        status INTEGER NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students (id) ON DELETE CASCADE,
        UNIQUE(studentId, date)
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE students ADD COLUMN year INTEGER DEFAULT 1');
        await db.execute('ALTER TABLE students ADD COLUMN semester INTEGER DEFAULT 1');
      } catch (e) {
        print('Upgrade error: $e');
      }
    }
  }

  // ---------- Student CRUD ----------
  Future<int> insertStudent(Map<String, dynamic> student) async {
    final db = await database;
    return await db.insert('students', {
      'name': student['name'],
      'rollNumber': student['rollNumber'],
      'course': student['course'],
      'year': student['year'] ?? 1,
      'semester': student['semester'] ?? 1,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<List<Map<String, dynamic>>> getAllStudents() async {
    final db = await database;
    final result = await db.query('students', orderBy: 'course ASC, year ASC, semester ASC, rollNumber ASC');
    return result.map((map) {
      return {
        ...map,
        'year': (map['year'] as num?)?.toInt() ?? 1,
        'semester': (map['semester'] as num?)?.toInt() ?? 1,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getStudentsByCourse(String course) async {
    final db = await database;
    final result = await db.query(
      'students',
      where: 'course = ?',
      whereArgs: [course],
      orderBy: 'rollNumber ASC',
    );
    return result.map((map) {
      return {
        ...map,
        'year': (map['year'] as num?)?.toInt() ?? 1,
        'semester': (map['semester'] as num?)?.toInt() ?? 1,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getStudentsByCourseYearSemester(
      String course, int year, int semester) async {
    final db = await database;
    final result = await db.query(
      'students',
      where: 'course = ? AND year = ? AND semester = ?',
      whereArgs: [course, year, semester],
      orderBy: 'rollNumber ASC',
    );
    return result.map((map) {
      return {
        ...map,
        'year': (map['year'] as num?)?.toInt() ?? year,
        'semester': (map['semester'] as num?)?.toInt() ?? semester,
      };
    }).toList();
  }

  Future<List<int>> getAvailableYearsForCourse(String course) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT year FROM students WHERE course = ? ORDER BY year ASC',
      [course],
    );
    return result.map((row) => (row['year'] as num?)?.toInt() ?? 0).where((y) => y > 0).toList();
  }

  Future<List<int>> getAvailableSemestersForCourseAndYear(String course, int year) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT semester FROM students WHERE course = ? AND year = ? ORDER BY semester ASC',
      [course, year],
    );
    return result.map((row) => (row['semester'] as num?)?.toInt() ?? 0).where((s) => s > 0).toList();
  }

  Future<List<String>> getAllCourses() async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT course FROM students ORDER BY course ASC');
    return result.map((e) => e['course'] as String).toList();
  }

  Future<int> updateStudent(int id, Map<String, dynamic> student) async {
    final db = await database;
    return await db.update('students', {
      'name': student['name'],
      'rollNumber': student['rollNumber'],
      'course': student['course'],
      'year': student['year'] ?? 1,
      'semester': student['semester'] ?? 1,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return await db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getStudentByRollNumber(String rollNumber) async {
    final db = await database;
    final result = await db.query(
      'students',
      where: 'rollNumber = ?',
      whereArgs: [rollNumber],
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getStudentById(int id) async {
    final db = await database;
    final result = await db.query('students', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      final map = result.first;
      return {
        ...map,
        'year': (map['year'] as num?)?.toInt() ?? 1,
        'semester': (map['semester'] as num?)?.toInt() ?? 1,
      };
    }
    return null;
  }

  Future<bool> rollNumberExists(String rollNumber, {int? excludeId}) async {
    final db = await database;
    String query = 'SELECT 1 FROM students WHERE rollNumber = ?';
    List<dynamic> args = [rollNumber];
    if (excludeId != null) {
      query += ' AND id != ?';
      args.add(excludeId);
    }
    final result = await db.rawQuery(query, args);
    return result.isNotEmpty;
  }

  // ---------- Attendance CRUD ----------
  Future<int> markAttendance(int studentId, String date, int status) async {
    final db = await database;
    return await db.insert('attendance', {
      'studentId': studentId,
      'date': date,
      'status': status,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> getAttendanceStatus(int studentId, String date) async {
    final db = await database;
    final result = await db.query(
      'attendance',
      where: 'studentId = ? AND date = ?',
      whereArgs: [studentId, date],
    );
    if (result.isNotEmpty) return result.first['status'] as int;
    return null;
  }

  Future<List<Map<String, dynamic>>> getAttendanceByStudentId(int studentId) async {
    final db = await database;
    return await db.query(
      'attendance',
      where: 'studentId = ?',
      whereArgs: [studentId],
      orderBy: 'date ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAttendanceByDateRange(
      String startDate, String endDate, {String? course}) async {
    final db = await database;
    String query = '''
      SELECT s.id, s.name, s.rollNumber, s.course, a.date, a.status
      FROM students s
      LEFT JOIN attendance a ON s.id = a.studentId AND a.date BETWEEN ? AND ?
    ''';
    List<dynamic> args = [startDate, endDate];
    if (course != null && course.isNotEmpty) {
      query += ' WHERE s.course = ?';
      args.add(course);
    }
    query += ' ORDER BY s.course, s.name, a.date';
    return await db.rawQuery(query, args);
  }

  Future<String> exportToCsv({String? course, String? startDate, String? endDate}) async {
    final db = await database;
    List<Map<String, dynamic>> data;
    if (startDate != null && endDate != null) {
      data = await getAttendanceByDateRange(startDate, endDate, course: course);
    } else {
      final students = await getAllStudents();
      if (students.isEmpty) return '';
      StringBuffer csv = StringBuffer();
      csv.writeln('Name,Roll Number,Course,Year,Semester,Date,Status');
      for (var student in students) {
        if (course != null && student['course'] != course) continue;
        final attendance = await db.query(
          'attendance',
          where: 'studentId = ?',
          whereArgs: [student['id']],
          orderBy: 'date ASC',
        );
        if (attendance.isEmpty) {
          csv.writeln('${student['name']},${student['rollNumber']},${student['course']},${student['year']},${student['semester']},,');
        } else {
          for (var record in attendance) {
            csv.writeln('${student['name']},${student['rollNumber']},${student['course']},${student['year']},${student['semester']},${record['date']},${record['status'] == 1 ? 'Present' : 'Absent'}');
          }
        }
      }
      return csv.toString();
    }
    if (data.isEmpty) return '';
    StringBuffer csv = StringBuffer();
    csv.writeln('Name,Roll Number,Course,Date,Status');
    for (var record in data) {
      csv.writeln('${record['name']},${record['rollNumber']},${record['course']},${record['date'] ?? ''},${record['status'] == 1 ? 'Present' : 'Absent'}');
    }
    return csv.toString();
  }

  Future<Map<String, int>> getAttendanceSummary(String startDate, String endDate, {String? course}) async {
    final db = await database;
    String query = '''
      SELECT 
        COUNT(DISTINCT CASE WHEN a.status = 1 THEN a.studentId END) as present_count,
        COUNT(DISTINCT s.id) as total_students,
        SUM(CASE WHEN a.status = 1 THEN 1 ELSE 0 END) as total_present,
        COUNT(a.id) as total_records
      FROM students s
      LEFT JOIN attendance a ON s.id = a.studentId AND a.date BETWEEN ? AND ?
    ''';
    List<dynamic> args = [startDate, endDate];
    if (course != null && course.isNotEmpty) {
      query += ' WHERE s.course = ?';
      args.add(course);
    }
    final result = await db.rawQuery(query, args);
    return {
      'presentCount': (result.first['present_count'] as num?)?.toInt() ?? 0,
      'totalStudents': (result.first['total_students'] as num?)?.toInt() ?? 0,
      'totalPresent': (result.first['total_present'] as num?)?.toInt() ?? 0,
      'totalRecords': (result.first['total_records'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('attendance');
    await db.delete('students');
  }
}