import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../widgets/text_paste_dialog.dart';
import '../service/fcm_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with TickerProviderStateMixin {
  int _selectedTab = 0;
  String _searchQuery = '';
  String _selectedFilter = 'all';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<DocumentSnapshot> _allUsers = [];
  List<DocumentSnapshot> _allMessages = [];
  int _usersPage = 0;
  int _usersPerPage = 30;
  bool _hasMoreUsers = true;
  bool _isLoadingMore = false;

  Map<String, dynamic> _dashboardCache = {};
  DateTime? _lastCacheUpdate;
  bool _isCacheLoading = false;

  late AnimationController _refreshController;
  late Animation<double> _refreshAnimation;

  String? _selectedViewCourse;
  bool _showStudentListView = false;

  @override
  void initState() {
    super.initState();
    _verifyAdminAccess();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);

    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _refreshAnimation = Tween(begin: 0.0, end: 1.0).animate(_refreshController);

    _setupFirebaseMessaging();
    _initializeData();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _refreshDashboard() async {
    _refreshController.forward(from: 0);
    await _precacheDashboardData();
  }

  Map<String, dynamic> _getMinimalDashboardData() {
    return {
      'users': <DocumentSnapshot>[],
      'teachers': 0,
      'students': 0,
      'activeUsers': 0,
      'total': 0,
    };
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Never';
    if (timestamp is Timestamp) {
      final now = DateTime.now();
      final date = timestamp.toDate();
      final difference = now.difference(date);
      if (difference.inDays == 0) return 'Today';
      if (difference.inDays == 1) return 'Yesterday';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return DateFormat('MMM d, yyyy').format(date);
    }
    return timestamp.toString();
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  // ===============================
  // 🆕 AUTO SEMESTER UPDATE LOGIC
  // ===============================
  Future<void> _autoUpdateSemester() async {
    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto Update Semester'),
        content: const Text(
          'This will automatically advance the semester for all students based on Delhi University academic calendar.\n\n'
              'Semester will increment by 1. If semester exceeds 6, year will increment and semester resets to 1.\n\n'
              'A log entry will be created and notifications can be sent. Proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
        ],
      ),
    );
    if (confirm != true) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Updating semesters for all students...'),
          ],
        ),
      ),
    );

    try {
      final studentsSnapshot = await FirebaseFirestore.instance.collection('students').get();
      int updatedCount = 0;
      final batch = FirebaseFirestore.instance.batch();

      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        String currentSemester = data['semester'] ?? 'Semester 1';
        String currentYear = data['year'] ?? '1 Year';

        // Parse semester number (e.g., "Semester 1" -> 1)
        int semesterNum = int.tryParse(currentSemester.split(' ')[1]) ?? 1;
        int newSemesterNum = semesterNum + 1;

        String newSemester = 'Semester $newSemesterNum';
        String newYear = currentYear;

        // If semester > 6, increment year and reset semester to 1
        if (newSemesterNum > 6) {
          newSemesterNum = 1;
          newSemester = 'Semester 1';
          // Increment year: "1 Year" -> "2 Year", etc.
          int yearNum = int.tryParse(currentYear.split(' ')[0]) ?? 1;
          if (yearNum < 3) {
            newYear = '${yearNum + 1} Year';
          } else {
            // Already final year, keep as is
            newYear = currentYear;
          }
        }

        // Only update if changed
        if (newSemester != currentSemester || newYear != currentYear) {
          batch.update(doc.reference, {
            'semester': newSemester,
            'year': newYear,
            'lastSemesterUpdate': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          updatedCount++;
        }
      }

      await batch.commit();

      // Log the operation
      await FirebaseFirestore.instance.collection('admin_audit_logs').add({
        'action': 'auto_semester_update',
        'timestamp': FieldValue.serverTimestamp(),
        'adminId': FirebaseAuth.instance.currentUser?.uid,
        'updatedCount': updatedCount,
        'details': 'Semester auto-update performed for all students.',
      });

      Navigator.pop(context); // Close progress dialog
      _showSnackBar('✅ Semester update complete! $updatedCount students updated.');
      _refreshDashboard();

      // Optionally send notification to students about semester change
      await _sendSemesterUpdateNotification(updatedCount);
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('❌ Error during semester update: $e', isError: true);
    }
  }

  Future<void> _sendSemesterUpdateNotification(int studentCount) async {
    try {
      final adminToken = await FirebaseMessaging.instance.getToken();
      final message = {
        'title': 'Semester Updated',
        'body': 'Your semester has been automatically updated according to DU academic calendar.',
        'data': {'type': 'semester_update'},
      };
      // In a real app, you'd send to all student tokens via cloud function.
      // Here we just record in notifications collection.
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': message['title'],
        'body': message['body'],
        'timestamp': FieldValue.serverTimestamp(),
        'targetGroup': 'students',
        'sentBy': FirebaseAuth.instance.currentUser?.uid,
      });
      print('Semester update notification recorded.');
    } catch (e) {
      print('Error recording notification: $e');
    }
  }

  // ===============================
  // EXISTING HELPER METHODS
  // ===============================

  Future<void> _showTextPasteDialog() async {
    await showDialog(
      context: context,
      builder: (context) => TextPasteDialog(
        onStudentAdded: (studentData, documentId) async {
          print('Student added with ID: $documentId');
        },
        onBatchComplete: (count) {
          _showSnackBar('✅ Successfully added $count students');
          _refreshDashboard();
          if (_showStudentListView) {
            setState(() {});
          }
        },
      ),
    );
  }

  Future<void> _showCourseSelection() async {
    final List<String> courses = await _getAllCourses();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Course'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: courses.isEmpty
              ? const Center(child: Text('No courses found'))
              : ListView.builder(
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              return ListTile(
                title: Text(course),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedViewCourse = course;
                    _showStudentListView = true;
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _getAllCourses() async {
    final snapshot = await FirebaseFirestore.instance.collection('students').get();
    final courses = <String>{};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data['course'] != null) {
        courses.add(data['course'].toString());
      }
    }
    return courses.toList()..sort();
  }

  Future<void> _deleteAllStudentData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning, color: Colors.red), SizedBox(width: 8), Text('Delete All Students')]),
        content: const Text('⚠️ WARNING: This will delete ALL student data from the database.\n\nThis action cannot be undone. Are you absolutely sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete All', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed == true) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Deleting all student data...')])));
      try {
        int deleted = await _deleteAllStudentsFromFirestore();
        Navigator.pop(context);
        _showSnackBar('✅ Deleted $deleted student records');
        setState(() { _showStudentListView = false; _selectedViewCourse = null; });
        _refreshDashboard();
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('❌ Error deleting data: $e', isError: true);
      }
    }
  }

  Future<void> _deleteStudentsByYear() async {
    String? selectedYear = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Year to Delete'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Choose the year of students to delete:'),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: ['1 Year', '2 Year', '3 Year'].map((year) => ElevatedButton(onPressed: () => Navigator.pop(context, year), child: Text(year))).toList()),
        ]),
      ),
    );
    if (selectedYear == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete all $selectedYear students? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed == true) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Deleting students...')])));
      try {
        int deleted = await _deleteStudentsByYearFromFirestore(selectedYear);
        Navigator.pop(context);
        _showSnackBar('✅ Deleted $deleted $selectedYear students');
        setState(() { _showStudentListView = false; _selectedViewCourse = null; });
        _refreshDashboard();
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('❌ Error deleting data: $e', isError: true);
      }
    }
  }

  Future<void> _deleteSingleStudent(String studentId) async {
    try {
      await FirebaseFirestore.instance.collection('students').doc(studentId).delete();
      _showSnackBar('✅ Student deleted successfully');
      _refreshDashboard();
      if (_showStudentListView) setState(() {});
    } catch (e) {
      _showSnackBar('❌ Failed to delete student: $e', isError: true);
    }
  }

  Future<int> _deleteAllStudentsFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance.collection('students').get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) batch.delete(doc.reference);
    await batch.commit();
    return snapshot.docs.length;
  }

  Future<int> _deleteStudentsByYearFromFirestore(String year) async {
    final snapshot = await FirebaseFirestore.instance.collection('students').where('year', isEqualTo: year).get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) batch.delete(doc.reference);
    await batch.commit();
    return snapshot.docs.length;
  }

  Stream<QuerySnapshot> _getStudentsByCourse(String course) {
    return FirebaseFirestore.instance.collection('students').where('course', isEqualTo: course).snapshots();
  }

  Future<void> _verifyAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pushReplacementNamed(context, '/login'); });
      return;
    }
    if (user.email?.toLowerCase() != 'surajncc2006@gmail.com') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin access restricted')));
        }
      });
      return;
    }
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await docRef.get();
    await docRef.set({
      'email': user.email,
      'displayName': 'Suraj',
      'studentName': 'Suraj',
      'rollNumber': 'admin',
      'isAdmin': true,
      'role': 'admin',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print('Admin user verified and updated in Firestore');
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      setState(() { _selectedTab = _tabController.index; });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _dashboardCache = _getMinimalDashboardData();
      WidgetsBinding.instance.addPostFrameCallback((_) { _precacheDashboardData(); });
      setState(() { _isLoading = false; });
    } catch (e) {
      print('Error initializing data: $e');
      setState(() { _dashboardCache = _getMinimalDashboardData(); _isLoading = false; });
    }
  }

  Future<void> _precacheDashboardData() async {
    if (_isCacheLoading) return;
    try {
      _isCacheLoading = true;
      final data = await _loadDashboardData();
      if (mounted) setState(() { _dashboardCache = data; _lastCacheUpdate = DateTime.now(); });
    } catch (e) { print('Error pre-caching dashboard data: $e'); }
    finally { _isCacheLoading = false; }
  }

  Future<void> _setupFirebaseMessaging() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      String? token = await FirebaseMessaging.instance.getToken();
      print('Admin device token: $token');
      FirebaseMessaging.onMessage.listen((RemoteMessage message) { print('Admin received message: ${message.notification?.title}'); });
    } catch (e) { print('Error setting up FCM: $e'); }
  }

  Future<Map<String, dynamic>> _loadDashboardData() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').orderBy('lastLoginAt', descending: true).limit(20).get();
      final users = usersSnapshot.docs;
      int teachers = 0, students = 0, activeUsers = 0;
      for (var user in users) {
        final data = user.data() as Map<String, dynamic>;
        if (data['role'] == 'teacher') teachers++;
        else if (data['role'] == 'student') students++;
        final lastLogin = data['lastLoginAt'] as Timestamp?;
        if (lastLogin != null && DateTime.now().difference(lastLogin.toDate()).inDays <= 7) activeUsers++;
      }
      return {'users': users, 'teachers': teachers, 'students': students, 'activeUsers': activeUsers, 'total': users.length};
    } catch (e) {
      print('Error loading dashboard data: $e');
      return {'users': [], 'teachers': 0, 'students': 0, 'activeUsers': 0, 'total': 0};
    }
  }

  Widget _buildLoadingScreen(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 80, height: 80, child: CircularProgressIndicator.adaptive(valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor), strokeWidth: 3)),
          const SizedBox(height: 24),
          Text('Loading Admin Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.grey[800])),
          const SizedBox(height: 12),
          Text('Please wait a moment', style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = isDarkMode ? Colors.grey[900]! : Colors.grey[50]!;
    final cardColor = isDarkMode ? Colors.grey[800]! : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: _isLoading
          ? _buildLoadingScreen(isDarkMode)
          : Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primaryColor, primaryColor.withOpacity(0.8)]),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(backgroundColor: Colors.white.withOpacity(0.2), child: const Icon(Icons.person, color: Colors.white)),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Admin Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                          Text('Welcome back', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                        ]),
                        const Spacer(),
                        IconButton(onPressed: _refreshDashboard, icon: AnimatedIcon(icon: AnimatedIcons.menu_arrow, progress: _refreshAnimation), color: Colors.white),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    indicator: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withOpacity(0.2)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: const [
                      Tab(icon: Icon(Icons.dashboard, size: 20), text: 'Dashboard'),
                      Tab(icon: Icon(Icons.people_alt, size: 20), text: 'Users'),
                      Tab(icon: Icon(Icons.message, size: 20), text: 'Messages'),
                      Tab(icon: Icon(Icons.analytics, size: 20), text: 'Analytics'),
                      Tab(icon: Icon(Icons.settings, size: 20), text: 'Settings'),
                      Tab(icon: Icon(Icons.security, size: 20), text: 'Security'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: backgroundColor,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDashboardTab(isDarkMode, cardColor),
                  _buildUsersTab(isDarkMode, cardColor),
                  _buildMessagesTab(isDarkMode, cardColor),
                  _buildAnalyticsTab(isDarkMode, cardColor),
                  _buildSettingsTab(isDarkMode, cardColor),
                  _buildSecurityTab(isDarkMode, cardColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== DASHBOARD TAB ==========
  Widget _buildDashboardTab(bool isDarkMode, Color cardColor) {
    final isCacheStale = _lastCacheUpdate == null || DateTime.now().difference(_lastCacheUpdate!).inMinutes > 5;
    if (isCacheStale && !_isCacheLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) { _precacheDashboardData(); });
    }

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildStatCard(title: 'Total Users', value: _dashboardCache['total']?.toString() ?? '0', icon: Icons.people, color: Colors.blue, isDarkMode: isDarkMode, cardColor: cardColor),
                _buildStatCard(title: 'Teachers', value: _dashboardCache['teachers']?.toString() ?? '0', icon: Icons.school, color: Colors.green, isDarkMode: isDarkMode, cardColor: cardColor),
                _buildStatCard(title: 'Students', value: _dashboardCache['students']?.toString() ?? '0', icon: Icons.group, color: Colors.orange, isDarkMode: isDarkMode, cardColor: cardColor),
                _buildStatCard(title: 'Active', value: '${_dashboardCache['activeUsers'] ?? 0}', icon: Icons.check_circle, color: Colors.purple, isDarkMode: isDarkMode, cardColor: cardColor),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(title: 'Quick Actions', isDarkMode: isDarkMode),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              childAspectRatio: 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildQuickActionCard(title: 'Send Message', icon: Icons.send, color: Colors.purple, onTap: _sendMessageToUsers, isDarkMode: isDarkMode, cardColor: cardColor),
                _buildQuickActionCard(title: 'Export Data', icon: Icons.download, color: Colors.blue, onTap: _exportData, isDarkMode: isDarkMode, cardColor: cardColor),
                _buildQuickActionCard(title: 'Announcement', icon: Icons.announcement, color: Colors.green, onTap: _sendAnnouncement, isDarkMode: isDarkMode, cardColor: cardColor),
                _buildQuickActionCard(title: 'Security', icon: Icons.security, color: Colors.teal, onTap: _viewSecurityReport, isDarkMode: isDarkMode, cardColor: cardColor),
              ],
            ),
            const SizedBox(height: 24),
            _buildDataManagementSection(isDarkMode, cardColor),
            const SizedBox(height: 24),
            _buildRecentActivitySection(isDarkMode, cardColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required bool isDarkMode}) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.grey[800])),
        const Spacer(),
        if (_lastCacheUpdate != null) Text('Updated ${_formatTimeAgo(_lastCacheUpdate!)}', style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
      ],
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color, required bool isDarkMode, required Color cardColor}) {
    return Container(
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
                const Spacer(),
                Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: isDarkMode ? Colors.white : Colors.grey[900])),
              ],
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Text(title, style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]))),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({required String title, required IconData icon, required Color color, required VoidCallback onTap, required bool isDarkMode, required Color cardColor}) {
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.1), width: 1)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.grey[800])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitySection(bool isDarkMode, Color cardColor) {
    final users = _dashboardCache['users'] as List<DocumentSnapshot>? ?? [];
    return Container(
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.grey[800])),
            const SizedBox(height: 16),
            if (users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(children: [Icon(Icons.people_outline, size: 48, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]), const SizedBox(height: 12), Text('No recent activity', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]))]),
              )
            else
              ...users.take(5).map((doc) {
                final user = doc.data() as Map<String, dynamic>;
                final isTeacher = user['role'] == 'teacher';
                final name = isTeacher ? user['teacherName'] ?? 'Unknown' : user['studentName'] ?? 'Unknown';
                final lastLogin = user['lastLoginAt'] as Timestamp?;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: isTeacher ? [Colors.blue, Colors.blue.shade300] : [Colors.green, Colors.green.shade300]), shape: BoxShape.circle),
                    child: Center(child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ),
                  title: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.grey[800])),
                  subtitle: Text(lastLogin != null ? 'Last login ${_formatTimeAgo(lastLogin.toDate())}' : 'Never logged in', style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
                  trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: isTeacher ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(isTeacher ? 'Teacher' : 'Student', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isTeacher ? Colors.blue : Colors.green))),
                );
              }).toList(),
            if (users.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: () { _tabController.animateTo(1); }, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)), child: Text('View All Users', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w500))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Data Management Section (updated with Auto Semester button)
  Widget _buildDataManagementSection(bool isDarkMode, Color cardColor) {
    return Container(
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.data_usage, color: Theme.of(context).primaryColor), const SizedBox(width: 8), Text('Student Data Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.grey[800]))]),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildDataActionCard('Paste Text', Icons.content_paste, Colors.teal, _showTextPasteDialog, isDarkMode, cardColor),
                _buildDataActionCard('View Students', Icons.visibility, Colors.green, _showCourseSelection, isDarkMode, cardColor),
                _buildDataActionCard('Delete by Year', Icons.delete_sweep, Colors.orange, _deleteStudentsByYear, isDarkMode, cardColor),
                _buildDataActionCard('Delete All', Icons.delete_forever, Colors.red, _deleteAllStudentData, isDarkMode, cardColor),
                // 🆕 NEW: Auto Semester Update Button
                _buildDataActionCard('Auto Semester', Icons.update, Colors.indigo, _autoUpdateSemester, isDarkMode, cardColor),
              ],
            ),
            if (_showStudentListView && _selectedViewCourse != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.school, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Students - $_selectedViewCourse',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.grey[800]),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { _showStudentListView = false; _selectedViewCourse = null; }); }),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(height: 400, child: _buildStudentListViewer(_selectedViewCourse!, isDarkMode)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentListViewer(String course, bool isDarkMode) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getStudentsByCourse(course),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(Icons.no_accounts, size: 48, color: Colors.grey), const SizedBox(height: 16), Text('No students found for $course')],
            ),
          );
        }
        final students = snapshot.data!.docs;
        return ListView.builder(
          itemCount: students.length,
          itemBuilder: (context, index) {
            final student = students[index].data() as Map<String, dynamic>;
            final studentId = students[index].id;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(student['rollNo']?.toString().substring(0, student['rollNo'].toString().length > 2 ? 2 : student['rollNo'].toString().length) ?? '?')),
                title: Text(student['name'] ?? 'Unknown'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Roll No: ${student['rollNo'] ?? 'N/A'}'),
                    Text('Section: ${student['section'] ?? 'N/A'} | Year: ${student['year'] ?? 'N/A'} | Sem: ${student['semester'] ?? 'N/A'}'),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteSingleStudent(studentId)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDataActionCard(String title, IconData icon, Color color, VoidCallback onTap, bool isDarkMode, Color cardColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2), width: 1)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white : Colors.grey[800])),
            ],
          ),
        ),
      ),
    );
  }

  // ========== USERS TAB (unchanged) ==========
  Widget _buildUsersTab(bool isDarkMode, Color cardColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: isDarkMode ? Colors.grey[850] : Colors.white,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search users by name, email, or ID...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
                onChanged: (value) { setState(() { _searchQuery = value; }); },
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', 'all', isDarkMode),
                    const SizedBox(width: 8),
                    _buildFilterChip('Teachers', 'teachers', isDarkMode),
                    const SizedBox(width: 8),
                    _buildFilterChip('Students', 'students', isDarkMode),
                    const SizedBox(width: 8),
                    _buildFilterChip('Active', 'active', isDarkMode),
                    const SizedBox(width: 8),
                    _buildFilterChip('Inactive', 'inactive', isDarkMode),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).limit(_usersPerPage).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return _buildUsersLoading(isDarkMode);
              if (snapshot.hasError) return _buildUsersError(snapshot.error.toString(), isDarkMode);
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildNoUsers(isDarkMode);
              _allUsers = snapshot.data!.docs;
              _hasMoreUsers = _allUsers.length == _usersPerPage;
              final filteredUsers = _applyFilters(_allUsers);
              return NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (!_isLoadingMore && _hasMoreUsers && scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) _loadMoreUsers();
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemCount: filteredUsers.length + (_hasMoreUsers ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == filteredUsers.length && _hasMoreUsers) return _buildLoadMoreButton(isDarkMode);
                    final user = filteredUsers[index].data() as Map<String, dynamic>;
                    final docId = filteredUsers[index].id;
                    return _buildUserCard(user, docId, isDarkMode, cardColor);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDarkMode) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) { setState(() { _selectedFilter = selected ? value : 'all'; }); },
      selectedColor: Theme.of(context).primaryColor,
      checkmarkColor: Colors.white,
      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
      labelStyle: TextStyle(color: isSelected ? Colors.white : (isDarkMode ? Colors.white : Colors.grey[800])),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Theme.of(context).primaryColor : Colors.transparent)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, String docId, bool isDarkMode, Color cardColor) {
    final isTeacher = user['role'] == 'teacher';
    final name = isTeacher ? user['teacherName'] ?? 'Unknown' : user['studentName'] ?? 'Unknown';
    final email = user['email'] ?? 'No email';
    final createdAt = _formatDate(user['createdAt']);
    return Container(
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))]),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(gradient: LinearGradient(colors: isTeacher ? [Colors.blue, Colors.blue.shade300] : [Colors.green, Colors.green.shade300]), shape: BoxShape.circle),
          child: Center(child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
        ),
        title: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.grey[800])),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(email, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: isTeacher ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(isTeacher ? 'Teacher' : 'Student', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: isTeacher ? Colors.blue : Colors.green))),
                const SizedBox(width: 8),
                Text('Joined $createdAt', style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.grey[500] : Colors.grey[500])),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
          onSelected: (value) => _handleUserAction(value, docId, user),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'view', child: ListTile(leading: Icon(Icons.visibility, size: 20), title: Text('View Details'), dense: true)),
            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, size: 20), title: Text('Edit User'), dense: true)),
            const PopupMenuItem(value: 'message', child: ListTile(leading: Icon(Icons.message, size: 20), title: Text('Send Message'), dense: true)),
            const PopupMenuItem(value: 'reset', child: ListTile(leading: Icon(Icons.lock_reset, size: 20), title: Text('Reset Password'), dense: true)),
            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, size: 20, color: Colors.red), title: const Text('Delete User', style: TextStyle(color: Colors.red)), dense: true)),
          ],
        ),
      ),
    );
  }

  void _handleUserAction(String action, String docId, Map<String, dynamic> user) {
    switch (action) {
      case 'view': _viewUserDetails(user); break;
      case 'edit': _editUser(docId, user); break;
      case 'message': _sendMessageToUser(user); break;
      case 'reset': _resetPassword(docId, user['email'] ?? ''); break;
      case 'delete': _deleteUser(docId, user['teacherName'] ?? user['studentName'] ?? 'Unknown'); break;
    }
  }

  List<DocumentSnapshot> _applyFilters(List<DocumentSnapshot> users) {
    var filtered = users;
    if (_selectedFilter != 'all') {
      filtered = filtered.where((doc) {
        final user = doc.data() as Map<String, dynamic>;
        if (_selectedFilter == 'teachers') return user['role'] == 'teacher';
        if (_selectedFilter == 'students') return user['role'] == 'student';
        if (_selectedFilter == 'active') {
          final lastLogin = user['lastLoginAt'] as Timestamp?;
          return lastLogin != null && DateTime.now().difference(lastLogin.toDate()).inDays <= 7;
        }
        if (_selectedFilter == 'inactive') {
          final lastLogin = user['lastLoginAt'] as Timestamp?;
          return lastLogin == null || DateTime.now().difference(lastLogin.toDate()).inDays > 30;
        }
        return true;
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((doc) {
        final user = doc.data() as Map<String, dynamic>;
        final name = (user['role'] == 'teacher' ? user['teacherName'] : user['studentName'])?.toLowerCase() ?? '';
        final email = (user['email'] ?? '').toLowerCase();
        final roll = (user['rollNumber'] ?? '').toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase()) || roll.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    return filtered;
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore || !_hasMoreUsers) return;
    setState(() => _isLoadingMore = true);
    try {
      final lastUser = _allUsers.last;
      final lastCreatedAt = lastUser['createdAt'] as Timestamp;
      final snapshot = await FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).startAfter([lastCreatedAt]).limit(_usersPerPage).get();
      if (snapshot.docs.isNotEmpty) {
        setState(() { _allUsers.addAll(snapshot.docs); _hasMoreUsers = snapshot.docs.length == _usersPerPage; });
      } else { _hasMoreUsers = false; }
    } catch (e) { print('Error loading more users: $e'); }
    finally { setState(() => _isLoadingMore = false); }
  }

  Widget _buildUsersLoading(bool isDarkMode) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator.adaptive(), const SizedBox(height: 16), Text('Loading users...', style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]))]));
  Widget _buildUsersError(String error, bool isDarkMode) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.error_outline, size: 60, color: isDarkMode ? Colors.grey[400] : Colors.grey[400]), const SizedBox(height: 16), Text('Failed to load users', style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.grey[400] : Colors.grey[600])), const SizedBox(height: 8), Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(error.length > 100 ? '${error.substring(0, 100)}...' : error, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)), const SizedBox(height: 20), ElevatedButton(onPressed: () { setState(() { _allUsers = []; }); }, child: const Text('Retry'))]));
  Widget _buildNoUsers(bool isDarkMode) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 60, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]), const SizedBox(height: 16), Text('No users found', style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.grey[400] : Colors.grey[600])), const SizedBox(height: 8), Text(_searchQuery.isNotEmpty ? 'Try a different search term' : 'No users match the selected filter', style: const TextStyle(fontSize: 12, color: Colors.grey))]));
  Widget _buildLoadMoreButton(bool isDarkMode) => Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: _isLoadingMore ? CircularProgressIndicator.adaptive() : ElevatedButton(onPressed: _loadMoreUsers, style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: const Text('Load More Users'))));

  void _viewUserDetails(Map<String, dynamic> user) { _showSnackBar('View user details: ${user['email']}'); }
  void _editUser(String docId, Map<String, dynamic> user) { _showSnackBar('Edit user: ${user['email']}'); }
  void _resetPassword(String docId, String email) { _showSnackBar('Reset password for: $email'); }
  void _deleteUser(String docId, String name) { _showSnackBar('Delete user: $name'); }

  // ========== MESSAGES TAB (unchanged) ==========
  Widget _buildMessagesTab(bool isDarkMode, Color cardColor) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('admin_messages').orderBy('timestamp', descending: true).limit(30).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.message_outlined, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No messages sent yet'),
              const SizedBox(height: 8),
              const Text('Send your first message using the + button', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ElevatedButton.icon(onPressed: _sendMessageToUsers, icon: const Icon(Icons.send), label: const Text('Send First Message')),
            ]),
          );
        }
        _allMessages = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _allMessages.length,
          itemBuilder: (context, index) {
            final message = _allMessages[index].data() as Map<String, dynamic>;
            final timestamp = message['timestamp'] as Timestamp?;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(child: Icon(Icons.message, color: _getGroupColor(message['targetGroup'] ?? 'all'))),
                title: Text(message['message'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('To: ${_getGroupDisplayName(message['targetGroup'] ?? 'all')} • ${timestamp != null ? DateFormat('MMM d, HH:mm').format(timestamp.toDate()) : 'Unknown date'}'),
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteMessage(_allMessages[index].id, message['message'] ?? '')),
                onTap: () => _showMessageDetails(message),
              ),
            );
          },
        );
      },
    );
  }

  Color _getGroupColor(String group) => group == 'teachers' ? Colors.blue : group == 'students' ? Colors.green : Colors.purple;
  String _getGroupDisplayName(String group) => group == 'teachers' ? 'Teachers' : group == 'students' ? 'Students' : 'All Users';

  // ========== ANALYTICS TAB (unchanged) ==========
  Widget _buildAnalyticsTab(bool isDarkMode, Color cardColor) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAnalyticsData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: Text('No analytics data'));
        final data = snapshot.data!;
        final total = data['total'] as int;
        final teachers = data['teachers'] as int;
        final students = data['students'] as int;
        final activeUsers = data['activeUsers'] as int;
        final recentUsers = data['recentUsers'] as int;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('User Distribution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      if (total > 0) ...[
                        SizedBox(
                          height: 200,
                          child: Center(
                            child: Stack(
                              children: [
                                SizedBox(width: 200, height: 200, child: CircularProgressIndicator(value: teachers / total, strokeWidth: 20, backgroundColor: Colors.grey.shade200)),
                                Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$total', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)), const Text('Total Users')])),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          Row(children: [Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)), const SizedBox(width: 4), Text('Teachers: $teachers')]),
                          Row(children: [Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)), const SizedBox(width: 4), Text('Students: $students')]),
                        ]),
                      ] else const Text('No users yet'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildStatRow('Active Users (7d)', '$activeUsers / $total', total > 0 ? activeUsers / total : 0),
                      const SizedBox(height: 12),
                      _buildStatRow('New Users (7d)', '$recentUsers', total > 0 ? recentUsers / total : 0),
                      const SizedBox(height: 12),
                      _buildStatRow('Engagement Rate', '${total > 0 ? ((activeUsers / total) * 100).toStringAsFixed(1) : 0}%', total > 0 ? activeUsers / total : 0),
                      const SizedBox(height: 12),
                      _buildStatRow('Growth Rate', '${total > 0 ? ((recentUsers / total) * 100).toStringAsFixed(1) : 0}%', total > 0 ? recentUsers / total : 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatRow(String title, String value, double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: progress.clamp(0.0, 1.0), backgroundColor: Colors.grey.shade200),
      ],
    );
  }

  Future<Map<String, dynamic>> _loadAnalyticsData() async {
    final users = await FirebaseFirestore.instance.collection('users').get();
    int teachers = 0, students = 0, active = 0, recent = 0;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    for (var doc in users.docs) {
      final data = doc.data();
      if (data['role'] == 'teacher') teachers++;
      else if (data['role'] == 'student') students++;
      final lastLogin = data['lastLoginAt'] as Timestamp?;
      if (lastLogin != null && DateTime.now().difference(lastLogin.toDate()).inDays <= 7) active++;
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null && createdAt.toDate().isAfter(weekAgo)) recent++;
    }
    return {'total': users.docs.length, 'teachers': teachers, 'students': students, 'activeUsers': active, 'recentUsers': recent};
  }

  // ========== SETTINGS TAB ==========
  Widget _buildSettingsTab(bool isDarkMode, Color cardColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(child: ListTile(title: const Text('Change Master Password'), subtitle: const Text('Update admin password'), leading: const Icon(Icons.lock), trailing: const Icon(Icons.chevron_right), onTap: () => _showSnackBar('Feature coming soon'))),
          Card(child: ListTile(title: const Text('Clear Cache'), subtitle: const Text('Clear all cached data'), leading: const Icon(Icons.delete_sweep), trailing: const Icon(Icons.chevron_right), onTap: _clearSystemCache)),
          Card(child: ListTile(title: const Text('Export Data'), subtitle: const Text('Export all data as CSV'), leading: const Icon(Icons.download), trailing: const Icon(Icons.chevron_right), onTap: _exportData)),
          Card(child: ListTile(title: const Text('Backup Database'), subtitle: const Text('Create system backup'), leading: const Icon(Icons.backup), trailing: const Icon(Icons.chevron_right), onTap: _backupDatabase)),
          Card(child: ListTile(title: const Text('Notification Settings'), subtitle: const Text('Configure notifications'), leading: const Icon(Icons.notifications), trailing: const Icon(Icons.chevron_right), onTap: () => _showSnackBar('Notification settings'))),
        ],
      ),
    );
  }

  void _clearSystemCache() { _showSnackBar('Cache cleared'); setState(() { _dashboardCache = _getMinimalDashboardData(); _allUsers.clear(); _allMessages.clear(); _lastCacheUpdate = null; }); }
  void _backupDatabase() { _showSnackBar('Backup created'); }
  void _exportData() { _showSnackBar('Exporting data...'); }
  void _sendAnnouncement() { _showSnackBar('Sending announcement...'); }
  void _viewSecurityReport() { _showSnackBar('Viewing security report...'); }

  // ========== SECURITY TAB ==========
  Widget _buildSecurityTab(bool isDarkMode, Color cardColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(child: ListTile(title: const Text('Security Report'), subtitle: const Text('View security report'), leading: const Icon(Icons.security), trailing: const Icon(Icons.chevron_right), onTap: () => _showSnackBar('Security report'))),
          Card(child: ListTile(title: const Text('Audit Logs'), subtitle: const Text('View system audit logs'), leading: const Icon(Icons.history), trailing: const Icon(Icons.chevron_right), onTap: _viewAuditLogs)),
          Card(child: ListTile(title: const Text('Blocked Users'), subtitle: const Text('Manage blocked users'), leading: const Icon(Icons.block), trailing: const Icon(Icons.chevron_right), onTap: () => _showSnackBar('Blocked users'))),
          Card(child: ListTile(title: const Text('Login History'), subtitle: const Text('View login attempts'), leading: const Icon(Icons.login), trailing: const Icon(Icons.chevron_right), onTap: () => _showSnackBar('Login history'))),
        ],
      ),
    );
  }

  void _viewAuditLogs() async { _showSnackBar('Loading audit logs...'); }

  // ========== MESSAGE SENDING METHODS ==========
  Future<void> _sendMessageToUsers() async {
    TextEditingController msgController = TextEditingController();
    String targetGroup = 'all';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: msgController, maxLines: 3, decoration: const InputDecoration(hintText: 'Enter your message...'), autofocus: true),
            const SizedBox(height: 16),
            const Text('Send to:', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(child: RadioListTile(title: const Text('All'), value: 'all', groupValue: targetGroup, onChanged: (v) => targetGroup = v.toString())),
                Expanded(child: RadioListTile(title: const Text('Teachers'), value: 'teachers', groupValue: targetGroup, onChanged: (v) => targetGroup = v.toString())),
                Expanded(child: RadioListTile(title: const Text('Students'), value: 'students', groupValue: targetGroup, onChanged: (v) => targetGroup = v.toString())),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async { Navigator.pop(context); await _processMessageSending(msgController.text, targetGroup); }, child: const Text('Send')),
        ],
      ),
    );
  }

  Future<void> _processMessageSending(String message, String targetGroup) async {
    if (message.trim().isEmpty) { _showSnackBar('Please enter a message', isError: true); return; }
    _showSnackBar('Sending message...');
    await Future.delayed(const Duration(seconds: 1));
    _showSnackBar('✅ Message sent successfully to $targetGroup');
  }

  void _showMessageDetails(Map<String, dynamic> message) { _showSnackBar('Message details: ${message['message']}'); }
  Future<void> _deleteMessage(String messageId, String messageText) async { _showSnackBar('Message deleted'); }
  void _sendMessageToUser(Map<String, dynamic> user) { _showSnackBar('Send message to ${user['email']}'); }
}