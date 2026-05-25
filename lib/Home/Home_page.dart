import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../Student/student_qr_screen.dart';
import '../basic_feture/ProfileScreen.dart';
import '../service/notifications_screen.dart';
import '../Teacher/teacher_attendance_screen.dart';
import '../basic_feture/SettingsScreen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _userRole;
  bool _isProvider = false;
  String? _userId;
  String? _rollNumber;
  String? _teacherName;
  String? _selectedCourse;
  int? _selectedSemester;
  String? _studentName;
  String? _studentGender;
  List<String>? _subjects;
  String? _userEmail;
  bool _isLoading = true;
  DateTime? _lastLogin;
  double _sidebarWidth = 280;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isAdmin = false;
  String? _userPhotoUrl;
  String? _selectedYear;
  String? _selectedSection;

  // Local profile image
  File? _selectedProfileImage;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadUserProfile();
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email?.toLowerCase() == 'surajncc2006@gmail.com') {
      print('✅ Setting admin status for: ${user.email}');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_admin', true);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isAdmin': true,
        'email': user.email,
        'displayName': 'Suraj',
        'rollNumber': 'admin',
        'role': 'admin',
      }, SetOptions(merge: true));
      setState(() {
        _isAdmin = true;
      });
    } else {
      print('❌ Not admin. User: ${user?.email}');
    }
  }

  ImageProvider? _getProfileImageProvider() {
    if (_selectedProfileImage != null) {
      return FileImage(_selectedProfileImage!);
    }
    if (_userPhotoUrl != null && _userPhotoUrl!.isNotEmpty) {
      return NetworkImage(_userPhotoUrl!);
    }
    return null;
  }

  DecorationImage? _getSidebarProfileDecorationImage() {
    if (_selectedProfileImage != null) {
      return DecorationImage(
        image: FileImage(_selectedProfileImage!),
        fit: BoxFit.cover,
      );
    }
    if (_userPhotoUrl != null && _userPhotoUrl!.isNotEmpty) {
      return DecorationImage(
        image: NetworkImage(_userPhotoUrl!),
        fit: BoxFit.cover,
      );
    }
    return null;
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    // First load from SharedPreferences
    String? storedRole = prefs.getString('user_role');
    bool isTeacher = prefs.getBool('is_teacher') == true;
    final isAdminFromPrefs = prefs.getBool('is_admin') == true;
    final isAdminEmail = user?.email?.toLowerCase() == 'surajncc2006@gmail.com';

    setState(() {
      if (isTeacher) {
        _userRole = 'Teacher';
      } else if (storedRole == 'admin' || isAdminFromPrefs || isAdminEmail) {
        _userRole = 'Admin';
        _isAdmin = true;
      } else {
        _userRole = 'Student';
      }

      _rollNumber = prefs.getString('roll_number');
      _teacherName = prefs.getString('teacher_name');
      _selectedCourse = prefs.getString('selected_course');
      _selectedSemester = prefs.getInt('selected_semester');
      _selectedYear = prefs.getString('selected_year');
      _selectedSection = prefs.getString('selected_section');
      _studentName = prefs.getString('student_name');
      _studentGender = prefs.getString('student_gender');
      _subjects = prefs.getStringList('selected_subjects');
      _userEmail = user?.email ?? prefs.getString('email');
      _userId = user?.uid;
      _userPhotoUrl = user?.photoURL;
      _isAdmin = isAdminFromPrefs || isAdminEmail || storedRole == 'admin';
    });

    final profileImagePath = prefs.getString('profile_image_path');
    if (profileImagePath != null && File(profileImagePath).existsSync()) {
      setState(() {
        _selectedProfileImage = File(profileImagePath);
      });
    }

    // Then load/refresh from Firestore to get latest data
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          setState(() {
            // Update from Firestore
            if (data?['displayName'] != null && _studentName == null) {
              _studentName = data?['displayName'];
            }
            if (data?['teacherName'] != null && _teacherName == null) {
              _teacherName = data?['teacherName'];
            }
            if (data?['rollNumber'] != null) {
              _rollNumber = data?['rollNumber'];
            }
            if (data?['course'] != null) {
              _selectedCourse = data?['course'];
            }
            if (data?['year'] != null) {
              _selectedYear = data?['year'];
            }
            if (data?['semester'] != null) {
              _selectedSemester = _parseSemesterNumber(data?['semester']);
            }
            if (data?['section'] != null) {
              _selectedSection = data?['section'];
            }
            if (data?['gender'] != null) {
              _studentGender = data?['gender'];
            }
            if (_subjects == null || _subjects!.isEmpty) {
              _subjects = List<String>.from(data?['subjects'] ?? []);
            }
            _lastLogin = data?['lastLoginAt']?.toDate();
            _userPhotoUrl ??= data?['photoUrl'];
            if (data?['isAdmin'] == true) {
              _isAdmin = true;
              _userRole = 'Admin';
            }
          });

          // Update SharedPreferences with latest data (No await needed here)
          if (data?['rollNumber'] != null) {
            prefs.setString('roll_number', data?['rollNumber']);
          }
          if (data?['course'] != null) {
            prefs.setString('selected_course', data?['course']);
          }
          if (data?['year'] != null) {
            prefs.setString('selected_year', data?['year']);
          }
          if (data?['semester'] != null) {
            prefs.setInt(
                'selected_semester', _parseSemesterNumber(data?['semester']));
          }
          if (data?['section'] != null) {
            prefs.setString('selected_section', data?['section']);
          }
          if (data?['gender'] != null) {
            prefs.setString('student_gender', data?['gender']);
          }
          if (data?['displayName'] != null) {
            prefs.setString('student_name', data?['displayName']);
            prefs.setString('user_name', data?['displayName']);
          }
        }
      } catch (e) {
        print('Error loading Firebase data: $e');
      }
    }

    setState(() {
      _isLoading = false;
    });

    print('=== User Profile Loaded ===');
    print('Role: $_userRole');
    print('Admin: $_isAdmin');
    print('Student Name: $_studentName');
    print('Roll Number: $_rollNumber');
    print('Course: $_selectedCourse');
    print('Year: $_selectedYear');
    print('Semester: $_selectedSemester');
    print('Section: $_selectedSection');
    print('===========================');
  }

  int _parseSemesterNumber(dynamic semester) {
    if (semester == null) return 1;
    if (semester is int) return semester;
    final str = semester.toString();
    final match = RegExp(r'\d+').firstMatch(str);
    return match != null ? int.parse(match.group(0)!) : 1;
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    ).then((_) => _loadUserProfile());
  }

  void _openSettingsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    ).then((_) => _loadUserProfile());
  }

  Future<String?> _saveImageToLocal(File imageFile) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';
      final savedImage = await imageFile.copy(savedPath);
      return savedImage.path;
    } catch (e) {
      print('Error saving image: $e');
      return null;
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final savedPath = await _saveImageToLocal(File(pickedFile.path));
        if (savedPath != null) {
          setState(() {
            _selectedProfileImage = File(savedPath);
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile_image_path', savedPath);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile photo updated'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage();
                },
              ),
              if (_selectedProfileImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo'),
                  onTap: () async {
                    Navigator.pop(context);
                    if (_selectedProfileImage != null) {
                      await _selectedProfileImage!.delete();
                    }
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('profile_image_path');
                    setState(() {
                      _selectedProfileImage = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile photo removed'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              Navigator.pushReplacementNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ==================== QUICK ACTIONS GRID ====================
  Widget _buildDashboardGrid() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final crossAxisCount = isMobile ? 2 : 3;

    List<Map<String, dynamic>> actions = [];

    // Student actions
    if (_userRole == 'Student') {
      actions.add({
        'icon': Icons.schedule,
        'title': 'Timetable',
        'subtitle': 'View your schedule',
        'color': Colors.blue.shade700,
        'onTap': () {
          Navigator.pushNamed(context, '/timetable');
        },
      });
      actions.add({
        'icon': Icons.qr_code,
        'title': 'My QR Code',
        'subtitle': 'Show to teacher',
        'color': Colors.purple.shade700,
        'onTap': () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const StudentQRCodeScreen()));
        },
      });
    }
    // Teacher actions
    else if (_userRole == 'Teacher') {
      actions.add({
        'icon': Icons.schedule,
        'title': 'Timetable',
        'subtitle': 'View schedule',
        'color': Colors.blue.shade700,
        'onTap': () {
          Navigator.pushNamed(context, '/timetable');
        },
      });
      actions.add({
        'icon': Icons.checklist,
        'title': 'Attendance Diary',
        'subtitle': 'Mark & manage attendance',
        'color': Colors.green.shade700,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TeacherAttendanceScreen()),
          );
        },
      });
    }

    // Profile action for all users
    actions.add({
      'icon': Icons.person,
      'title': 'Profile',
      'subtitle': 'Edit profile',
      'color': Colors.cyan.shade700,
      'onTap': _openProfileScreen,
    });

    // Admin action
    if (_isAdmin) {
      actions.add({
        'icon': Icons.admin_panel_settings,
        'title': 'Admin',
        'subtitle': 'Admin panel',
        'color': Colors.red.shade700,
        'onTap': () {
          Navigator.pushNamed(context, '/admin');
        },
      });
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: isMobile ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return _buildDashboardCard(
                icon: action['icon'] as IconData,
                title: action['title'] as String,
                subtitle: action['subtitle'] as String,
                color: action['color'] as Color,
                onTap: action['onTap'] as VoidCallback,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.1),
                color.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 50 : 60,
        isMobile ? 16 : 24,
        20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade800,
            Colors.blue.shade600,
            Colors.indigo.shade600,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isMobile)
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              const Spacer(),

              // Notification Icon with Unread Count
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('userId', isEqualTo: userId)
                    .where('read', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData && snapshot.data != null) {
                    unreadCount = snapshot.data!.docs.length;
                  }

                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none,
                            color: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NotificationsScreen(),
                            ),
                          );
                        },
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(width: 8),

              // Profile Image
              GestureDetector(
                onTap: _showImageOptions,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      backgroundImage: _getProfileImageProvider(),
                      child: _getProfileImageProvider() == null
                          ? Text(
                              (_studentName?.isNotEmpty == true
                                      ? _studentName!.substring(0, 1)
                                      : _teacherName?.isNotEmpty == true
                                          ? _teacherName!.substring(0, 1)
                                          : 'U')
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Greeting
          Text(
            '${_getGreeting()},',
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.w300,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 4),

          // User Name
          GestureDetector(
            onTap: _openProfileScreen,
            child: Text(
              _studentName ?? _teacherName ?? 'User',
              style: TextStyle(
                fontSize: isMobile ? 24 : 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),

          // User Details Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_userEmail != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.email, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _userEmail!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_rollNumber != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.numbers, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Roll: $_rollNumber',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              if (_selectedCourse != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        _selectedCourse!,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              if (_selectedSemester != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Sem $_selectedSemester',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              if (_selectedSection != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Sec: $_selectedSection',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              if (_isAdmin)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.admin_panel_settings,
                          size: 14, color: Colors.red.shade100),
                      const SizedBox(width: 6),
                      Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade100,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Edit Profile Button
          OutlinedButton.icon(
            onPressed: _openProfileScreen,
            icon: const Icon(Icons.edit, size: 16, color: Colors.white),
            label: const Text(
              'Edit Profile',
              style: TextStyle(color: Colors.white),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SIDEBAR ====================
  Widget _buildUserSidebar() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width:
          isMobile ? MediaQuery.of(context).size.width * 0.85 : _sidebarWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 3,
            offset: const Offset(5, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _openProfileScreen,
            child: Container(
              height: screenHeight * 0.25,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade900,
                    Colors.blue.shade700,
                    Colors.purple.shade600,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: isMobile ? 70 : 90,
                    height: isMobile ? 70 : 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      gradient: (_selectedProfileImage == null &&
                              (_userPhotoUrl == null || _userPhotoUrl!.isEmpty))
                          ? LinearGradient(
                              colors: [
                                Colors.blue.shade300,
                                Colors.purple.shade300,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      image: _getSidebarProfileDecorationImage(),
                    ),
                    child: (_selectedProfileImage == null &&
                            (_userPhotoUrl == null || _userPhotoUrl!.isEmpty))
                        ? Center(
                            child: Text(
                              (_studentName?.isNotEmpty == true
                                      ? _studentName!.substring(0, 1)
                                      : _teacherName?.isNotEmpty == true
                                          ? _teacherName!.substring(0, 1)
                                          : 'U')
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: isMobile ? 28 : 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _studentName ?? _teacherName ?? 'User',
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userRole ?? 'Student',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSidebarMenuItem(
                          icon: Icons.person_outline,
                          label: 'Profile',
                          onTap: _openProfileScreen,
                        ),
                        const SizedBox(height: 12),
                        _buildSidebarMenuItem(
                          icon: Icons.school_outlined,
                          label: 'Academics',
                          onTap: () {
                            Navigator.pop(context);
                            _showAcademicsDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoCard(
                          icon: Icons.email_outlined,
                          title: 'Email',
                          value: _userEmail ?? 'Not provided',
                          color: Colors.blue.shade700,
                        ),
                        if (_rollNumber != null)
                          _buildInfoCard(
                            icon: Icons.badge_outlined,
                            title: 'Roll Number',
                            value: _rollNumber!,
                            color: Colors.green.shade700,
                          ),
                        if (_selectedCourse != null)
                          _buildInfoCard(
                            icon: Icons.school_outlined,
                            title: 'Course',
                            value: _selectedCourse!,
                            color: Colors.orange.shade700,
                          ),
                        if (_selectedYear != null)
                          _buildInfoCard(
                            icon: Icons.calendar_month_outlined,
                            title: 'Year',
                            value: _selectedYear!,
                            color: Colors.deepPurple.shade700,
                          ),
                        if (_selectedSemester != null)
                          _buildInfoCard(
                            icon: Icons.numbers_outlined,
                            title: 'Semester',
                            value: 'Semester $_selectedSemester',
                            color: Colors.purple.shade700,
                          ),
                        if (_selectedSection != null)
                          _buildInfoCard(
                            icon: Icons.group_outlined,
                            title: 'Section',
                            value: _selectedSection!,
                            color: Colors.teal.shade700,
                          ),
                        if (_studentGender != null)
                          _buildInfoCard(
                            icon: Icons.person_outline,
                            title: 'Gender',
                            value: _studentGender!,
                            color: Colors.teal.shade700,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _buildSidebarMenuItem(
                          icon: Icons.settings_outlined,
                          label: 'App Settings',
                          onTap: () {
                            Navigator.pop(context);
                            _openSettingsScreen();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildSidebarMenuItem(
                          icon: Icons.help_outline,
                          label: 'Help & Support',
                          onTap: () {
                            Navigator.pop(context);
                            _showHelpDialog();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildSidebarMenuItem(
                          icon: Icons.info_outline,
                          label: 'About',
                          onTap: () {
                            Navigator.pop(context);
                            _showAboutDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 16, bottom: 32),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                        ),
                        icon: const Icon(Icons.logout, size: 20),
                        label: const Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== DIALOGS ====================
  void _showAcademicsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Academic Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedCourse != null)
              ListTile(
                leading: const Icon(Icons.school),
                title: const Text('Course'),
                subtitle: Text(_selectedCourse!),
              ),
            if (_selectedYear != null)
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Year'),
                subtitle: Text(_selectedYear!),
              ),
            if (_selectedSemester != null)
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Semester'),
                subtitle: Text('Semester $_selectedSemester'),
              ),
            if (_selectedSection != null)
              ListTile(
                leading: const Icon(Icons.group),
                title: const Text('Section'),
                subtitle: Text(_selectedSection!),
              ),
            if (_subjects != null && _subjects!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.book),
                title: const Text('Subjects'),
                subtitle: Text('${_subjects!.length} subjects enrolled'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const Text('For assistance, contact support@campusclock.com'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Campus Clock'),
        content: const Text(
          'Campus Clock v1.0.0\n\n'
          'Shyam Lal College Timetable Management System\n'
          'Developed for SLC students and faculty.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
              ),
              const SizedBox(height: 20),
              Text(
                'Loading your profile...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile ? _buildUserSidebar() : null,
      backgroundColor: Colors.grey.shade50,
      body: isMobile
          ? SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 8),
                    _buildDashboardGrid(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildUserSidebar(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 8),
                          _buildDashboardGrid(),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
