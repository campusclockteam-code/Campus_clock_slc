import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'timetable_web_screen.dart';
import '../basic_feture/ProfileScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.8, end: 1.1), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.1, end: 1.0), weight: 50),
    ]).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeIn),
      ),
    );

    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Timetable Search'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => _openProfileScreen(),
          ),
        ],
      ),
      body: const _TimetableTab(),
    );
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }
}

class _TimetableTab extends StatefulWidget {
  const _TimetableTab();

  @override
  State<_TimetableTab> createState() => _TimetableTabState();
}

class _TimetableTabState extends State<_TimetableTab> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late AnimationController _controller;
  late Animation<double> _formAnimation;

  String? _classValue;
  String? _semesterValue;
  String? _sectionValue;
  String? _teacherValue;
  String? _roomValue;
  String? _dayValue;
  String? _periodValue;

  // For searchable fields
  final TextEditingController _classSearchController = TextEditingController();
  final TextEditingController _teacherSearchController = TextEditingController();
  final TextEditingController _roomSearchController = TextEditingController();

  // Auto-fill data from user profile
  String? _userClassName;
  String? _userSemester;

  // Real SLC College Data
  final List<String> _classes = [
    'B.Sc. (Physical Science Hons) Physics',
    'Master of Arts',
    'GE/SEC/VAC/DSE/AEC-For All Students',
    'BOTANY',
    'B.Sc.Math(Hons.)',
    'Chemistry Hons.',
    'B.Com.(Prog)',
    'B.Sc Physical Science(CS)',
    'B.Sc Physical Science(Elec)',
    'B.A.(Prog.)',
    'B.A(H) Political Science',
    'B.Sc Physical Science(Chem)',
    'B.A(H) History',
    'BA.(H) Hindi',
    'B.A(H)English',
    'B.A(H) Economics',
    'B.Com.(Hons)',
  ];

  final List<String> _semesters = ['II', 'IV', 'VI', 'VIII'];
  final List<String> _sections = ['A', 'B', 'C'];
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _periods = [
    'Period 1 (8:00-9:00)',
    'Period 2 (9:00-10:00)',
    'Period 3 (10:00-11:00)',
    'Period 4 (11:00-12:00)',
    'Period 5 (12:00-1:00)',
    'Period 6 (1:00-2:00)',
    'Period 7 (2:00-3:00)',
    'Period 8 (3:00-4:00)',
    'Period 9 (4:00-5:00)',
  ];

  // Actual SLC Teachers
  final List<String> _teachers = [
    'Dr. Kinshuk Majumdar',
    'Dr. Reeta Sharma',
    'Dr. Seema Guglani',
    'Dr. Srinivas Misra',
    'Ms. Manila Kohli',
    'Dr Pooja Gupta',
    'Dr Yukti Monga',
    'Dr. Abbasuddin Tapadar, M.',
    'Dr. Aditi Puri',
    'Dr. Ajay Shankar Bangwal',
    'Dr. Amanpreet Kaur',
    'Dr. Amit Kumar',
    'Dr. Amitabh Kumar',
    'Dr. Anant Kumar Upadhyay',
    'Dr. Anita',
    'Dr. Anita Sikandar',
    'Dr. Ankit Mittal',
    'Dr. Anuj Kumar Sharma',
    'Dr. Anurag Maurya',
    'Dr. Awanish Mishra',
    'Dr. Bharat Bhushan Garg',
    'Dr. Bisla Devi',
    'Dr. Deepika Kumari',
    'Dr. Diksha Khera',
    'Dr. Dipak Kumar Shukla',
    'Dr. Gayatri Chaturvedi',
    'Dr. Gurmeet Singh',
    'Dr. Hanumat Meena',
    'Dr. Himanshi Kalra',
    'Dr. Jasvir Singh',
    'Dr. Jaya Kakkar',
    'Dr. Jitender Kumar',
    'Dr. Jitendra Meena',
    'Dr. Jyoti Atri',
    'Dr. Kanika Solanki',
    'Dr. Kaushiki Shukla',
    'Dr. Kavita Yadav',
    'Dr. Komilla Suri',
    'Dr. Leena Singh',
    'Dr. Manish Kumar (comm)',
    'Dr. Manisha',
    'Dr. Mast Ram',
    'Dr. Megha Jain',
    'Dr. Monica Gambhir',
    'Dr. Monika Goyal',
    'Dr. Mukesh Kumar',
    'Dr. Mukta Rohatgi',
    'Dr. Nand Kishore',
    'Dr. Neelam Dabas',
    'Dr. Neha Bothra',
    'Dr. Nidhi Jain',
    'Dr. Nidhi Mishra',
    'Dr. Niranjan Chichuan',
    'Dr. Niti Agarwal',
    'Dr. Ompal Singh Yadav',
    'Dr. Padma Dechan',
    'Dr. Pawan K. Adewa',
    'Dr. Pawan Kharwar',
    'Dr. Pooja Gupta',
    'Dr. Prabhat Sharma',
    'Dr. Pradeep Kumar Sharma',
    'Dr. Pranav Dass',
    'Dr. Prem Lata Meena',
    'Dr. Priyanka Thakur',
    'Dr. Radha Bhola',
    'Dr. Radhika Gupta',
    'Dr. Raghvandra M',
    'Dr. Rahul Boadh',
    'Dr. Rajeshwari',
    'Dr. Rajkumar Prasad',
    'Dr. Rajni Arora',
    'Dr. Rakesh Meena',
    'Dr. Rakesh Pant',
    'Dr. Ramesh Kr. Burnwal',
    'Dr. Ravinder Kumar',
    'Dr. Ravindra Kumar',
    'Dr. Rekha Kaushik',
    'Dr. Richa Tyagi',
    'Dr. Rohan Mandal',
    'Dr. Rohit Jahari',
    'Dr. Romasa Shukla',
    'Dr. Sanjay Kumar',
    'Dr. Satyapriya Pandey',
    'Dr. Saubhagyalaxmi Singh',
    'Dr. Seema Dabas',
    'Dr. Shraddhanand Rai',
    'Dr. Shyam Sundar Prasad',
    'Dr. Sita Ram Kumbhar',
    'Dr. Subodh Kumar',
    'Dr. Sudhir Kumar Yadav',
    'Dr. Sujata Tewatia',
    'Dr. Suman',
    'Dr. Sumita Sharma',
    'Dr. Sunaina Zutshi',
    'Dr. Sunny Aggarwal',
    'Dr. Supriti Mishra',
    'Dr. Sushil Kumar',
    'Dr. Swati Yadav',
    'Dr. Triveni',
    'Dr. Upendera Kumar',
    'Dr. Varun Bhandari',
    'Dr. Vinod Kumar',
    'Dr. Vinod Kumar Nehra',
    'Dr. Virender',
    'Mr. Aakash Kumar Soni',
    'Mr. Amit Kapoor',
    'Mr. Balram Kindra',
    'Mr. Deepak Kumar',
    'Mr. Dipank',
    'Mr. Manish Kumar (pol Sci)',
    'Mr. Manraj Meena',
    'Mr. Nartam Vivekanand Motiram',
    'Mr. Nishant Kr. Singh',
    'Mr. Pankaj Kumar Chaudhary',
    'Mr. Parveen Kumar',
    'Mr. Raju Ram Meena',
    'Mr. Sandeep Kumar',
    'Mr. Sanjeev Kumar',
    'Mr. Sanoj Kumar',
    'Mr. Sumit Bhati',
    'Mr. Sumit Kumar',
    'Mr. Yogesh',
    'Mrs. Kavita Meena',
    'Ms. Annie Thomas Rojer',
    'Ms. Ashani Dhar',
    'Ms. Deepti Sharma',
    'Ms. Gunjan Khandelwal',
    'Ms. Jyoti Sharma',
    'Ms. Kiran Yadav',
    'Ms. Lakshmi',
    'Ms. Nabanita Deka',
    'Ms. Nandita Pal',
    'Ms. Palak Kakkar',
    'Ms. Poonam',
    'Ms. Priya Khanna',
    'Ms. Priyambada Gupta',
    'Ms. Priyanka Yadav',
    'Ms. Radhika Kundalia',
    'Ms. Rashmita Sahu',
    'Ms. Reena Yadav',
    'Ms. Shivali Kharbanda',
    'Ms. Shraddha Agrawal',
    'Ms. Shweta',
    'Ms. Sonia Mudel',
    'Ms. Suman Rani',
    'Ms. Swati',
    'Ms. Swati Rathi',
    'Prof. Arkaja Goswami',
    'Prof. Ashu Gupta',
    'Prof. Hemant Kukreti',
    'Prof. Kavita Arora',
    'Prof. Kusha Tiwari',
    'Prof. Narendra Singh',
    'Prof. Neena Shireesh',
    'Prof. Pravin Kumar',
    'Prof. Rabi Narayan Kar',
    'Prof. Ruchika Ramakrishnan',
    'Prof. Samrendra Kumar',
    'Prof. Vijay Kumar Sharma'
  ];

  // Actual SLC Room Numbers
  final List<String> _rooms = [
    'RN207_2 (77/77)',
    '1 (54/54)',
    '2 (40/40)',
    '28_2 (65/65)',
    '4 (40/40)',
    '5 (54/54)',
    '6 (45/45)',
    '7 (40/40)',
    '8 (30/30)',
    '19 (45/45)',
    '28 (65/65)',
    '102 (50/50)',
    '104 (50/50)',
    '108 (50/50)',
    '109 (50/50)',
    '111 (50/50)',
    '112 (50/50)',
    '114 (50/50)',
    'Botany Laboratory (30/30)',
    'C-LAB-1 (50/50)',
    'C-LAB-2 (25/25)',
    'C-LAB-3 (40/40)',
    'C-LAB-3_1 (40/40)',
    'CHEM LAB4 (40/40)',
    'Chem lab1 (50/50)',
    'Chem lab3 (50/50)',
    'Chem Lab 1 (50/50)',
    'Chem Lab SEC1 (50/50)',
    'Chem Lab SEC2 (50/50)',
    'Chem Lab SEC3 (50/50)',
    'Chem Lab SEC4 (50/50)',
    'Chem lab 2 (50/50)',
    'Chem lab 3 (50/50)',
    'Chem lab1 (50/50)',
    'Chem_Comp_Lab (20/20)',
    'Chem_Lab_SEC6 (50/50)',
    'Chemlab_1 (50/50)',
    'Chemlab_2 (50/50)',
    'Chemlab_3 (50/50)',
    'Chemlab_4 (50/50)',
    'ELECTRONICS LAB (30/30)',
    'Field Work (30/30)',
    'Knowledge Resource Center Lab 4 (25/25)',
    'Knowledge Resource Center Lab 4_1 (0/0)',
    'N11 (50/50)',
    'N12 (50/50)',
    'PHYSICS LAB (60/60)',
    'PHYSICS LAB (50/50)',
    'RN 37_ (28/28)',
    'RN1 (45/45)',
    'RN10 (60/60)',
    'RN101 (50/50)',
    'RN102 (50/50)',
    'RN103 (50/50)',
    'RN104 (50/50)',
    'RN105 (50/50)',
    'RN106 (50/50)',
    'RN107 (50/50)',
    'RN108 (60/60)',
    'RN109 (50/50)',
    'RN11 (0/0)',
    'RN110 (45/45)',
    'RN111 (45/45)',
    'RN112 (50/50)',
    'RN113 (50/50)',
    'RN114 (50/50)',
    'RN115 (50/50)',
    'RN116 (0/0)',
    'RN12 (50/50)',
    'RN13 (50/50)',
    'RN14 (50/50)',
    'RN15 (45/45)',
    'RN16 (50/50)',
    'RN17 (40/40)',
    'RN18 (40/40)',
    'RN19_1 (30/30)',
    'RN19_2 (45/45)',
    'RN2 (22/22)',
    'RN20 (45/45)',
    'RN201 (50/50)',
    'RN202 (60/60)',
    'RN203 (77/77)',
    'RN204 (77/77)',
    'RN205 (77/77)',
    'RN206 (50/50)',
    'RN207 (50/50)',
    'RN207_1 (77/77)',
    'RN208 (60/60)',
    'RN209 (50/50)',
    'RN20_1 (40/40)',
    'RN20_2 (40/40)',
    'RN21 (45/45)',
    'RN22 (45/45)',
    'RN23 (45/45)',
    'RN24 (40/40)',
    'RN25 (45/45)',
    'RN26 (60/60)',
    'RN27 (45/45)',
    'RN28 (45/45)',
    'RN29 (45/45)',
    'RN3 (60/60)',
    'RN30 (0/0)',
    'RN31 (0/0)',
    'RN32 (0/0)',
    'RN33 (0/0)',
    'RN34 (0/0)',
    'RN35 (50/50)',
    'RN36 (50/50)',
    'RN37 (45/45)',
    'RN37_1 (45/45)',
    'RN38 (40/40)',
    'RN39 (40/40)',
    'RN4 (45/45)',
    'RN6_1 (45/45)',
    'RN8_1 (45/45)',
    'RN9 (60/60)',
    'RN_19_2 (45/45)',
    'X1 (28/28)',
    'X2 (28/28)',
    'X3 (28/28)',
    'X4 (0/0)',
    'X5 (30/30)',
    'X6 (40/40)',
    'X7 (0/0)',
    'chemlab_7 (50/50)'
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _formAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );
    _controller.forward();
    _loadUserProfile();
  }

  // Helper method to get display name for UI
  String _getDisplayName(String? courseName) {
    if (courseName == null) return '';
    if (courseName == 'B.A.(Prog.)') return 'B.A. Program';
    if (courseName == 'B.Com.(Prog)') return 'B.Com';
    if (courseName == 'B.Com.(Hons)') return 'B.Com (Hons)';
    if (courseName == 'B.Sc Physical Science') return 'B.Sc. Physical Science';
    if (courseName == 'B.Sc Physical Science(CS)') return 'B.Sc Physical Science(CS)';
    if (courseName == 'B.Sc Physical Science(Elec)') return 'B.Sc Physical Science(Elec)';
    if (courseName == 'B.Sc Physical Science(Chem)') return 'B.Sc Physical Science(Chem)';
    if (courseName == 'B.A(H) Political Science') return 'B.A(H) Political Science';
    if (courseName == 'B.A(H) History') return 'B.A(H) History';
    if (courseName == 'BA.(H) Hindi') return 'BA.(H) Hindi';
    if (courseName == 'B.A(H)English') return 'B.A(H)English';
    if (courseName == 'B.A(H) Economics') return 'B.A(H) Economics';
    if (courseName == 'B.Sc. (Physical Science Hons) Physics') return 'B.Sc. (Physical Science Hons) Physics';
    if (courseName == 'B.Sc.Math(Hons.)') return 'B.Sc.Math(Hons.)';
    if (courseName == 'Chemistry Hons.') return 'Chemistry Hons.';
    if (courseName == 'BOTANY') return 'BOTANY';
    if (courseName == 'Master of Arts') return 'Master of Arts';
    if (courseName == 'GE/SEC/VAC/DSE/AEC-For All Students') return 'GE/SEC/VAC/DSE/AEC-For All Students';
    return courseName;
  }

  Future<void> _loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        // This is the EXACT dropdown value (e.g., "B.A.(Prog.)")
        _userClassName = prefs.getString('selected_course');

        // Handle semester – it could be stored as int or string
        final semesterObj = prefs.get('selected_semester');
        if (semesterObj is String) {
          _userSemester = semesterObj;
        } else if (semesterObj is int) {
          const semesterMap = {1: 'I', 2: 'II', 3: 'III', 4: 'IV', 5: 'V', 6: 'VI', 7: 'VII', 8: 'VIII'};
          _userSemester = semesterMap[semesterObj] ?? semesterObj.toString();
        } else {
          _userSemester = 'II';
        }

        // Auto-fill class if data exists - use the EXACT value for matching
        if (_userClassName != null && _userClassName!.isNotEmpty) {
          try {
            _classValue = _classes.firstWhere(
                  (cls) => cls == _userClassName || cls.contains(_userClassName!) || _userClassName!.contains(cls),
            );
          } catch (e) {
            _classValue = _userClassName;
          }
        }

        // Auto-fill semester
        if (_userSemester != null && _userSemester!.isNotEmpty) {
          _semesterValue = _semesters.contains(_userSemester)
              ? _userSemester
              : _semesters.first;
        }
      });
    } catch (e) {
      print('Error loading user profile: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _classSearchController.dispose();
    _teacherSearchController.dispose();
    _roomSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shyam Lal College',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                // Display user's course and semester if available using display name
                if (_userClassName != null || _userSemester != null)
                  Text(
                    '${_getDisplayName(_userClassName)} ${_userSemester != null ? 'Sem $_userSemester' : ''}'.trim(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _onClearFilters,
                tooltip: 'Clear',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero Header with SLC Logo
                _buildHeroHeader(),
                const SizedBox(height: 24),

                // Quick Actions
                _buildQuickActions(),
                const SizedBox(height: 24),

                // Main Form
                Transform.translate(
                  offset: Offset(0, _formAnimation.value * 20),
                  child: Opacity(
                    opacity: _formAnimation.value,
                    child: _buildFilterForm(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade800,
            Colors.purple.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // SLC College Title
          const Text(
            'SHYAMLAL COLLEGE',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          // Hindi Text
          const Text(
            'श्याम लाल कॉलेज',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontFamily: 'NotoSansDevanagari',
            ),
          ),
          const SizedBox(height: 4),
          // University Info
          const Text(
            '(University Of Delhi)',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.schedule, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Campus Clock',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shyam Lal College Timetable',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Find your schedule in seconds',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildActionChip(
          icon: Icons.today,
          label: 'Auto-fill Profile',
          color: Colors.green,
          onTap: _autoFillFromProfile,
        ),
        _buildActionChip(
          icon: Icons.refresh,
          label: 'Clear All',
          color: Colors.orange,
          onTap: _onClearFilters,
        ),
        _buildActionChip(
          icon: Icons.trending_up,
          label: 'Popular',
          color: Colors.purple,
          onTap: _fillPopularData,
        ),
        _buildActionChip(
          icon: Icons.person_search,
          label: 'Teacher',
          color: Colors.teal,
          onTap: () => _showSearchDialog('Teacher', _teachers, (value) {
            setState(() => _teacherValue = value);
          }),
        ),
        _buildActionChip(
          icon: Icons.place,
          label: 'Room No.',
          color: Colors.deepOrange,
          onTap: () => _showSearchDialog('Room No.', _rooms, (value) {
            setState(() => _roomValue = value);
          }),
        ),
      ],
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.filter_list, color: Colors.blue, size: 24),
              SizedBox(width: 12),
              Text(
                'Timetable Search',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your class details to find schedule',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              children: [
                // Class Selection
                _buildSearchableField(
                  label: 'Class',
                  value: _classValue,
                  items: _classes,
                  icon: Icons.school,
                  hintText: 'Select Class',
                  onChanged: (v) => setState(() => _classValue = v),
                ),
                const SizedBox(height: 16),

                // Semester Selection
                _buildEnhancedDropdown(
                  label: 'Semester',
                  value: _semesterValue,
                  items: _semesters,
                  icon: Icons.calendar_today,
                  hintText: 'Select Semester',
                  onChanged: (v) => setState(() => _semesterValue = v),
                ),
                const SizedBox(height: 16),

                // Section Selection
                _buildEnhancedDropdown(
                  label: 'Section',
                  value: _sectionValue,
                  items: _sections,
                  icon: Icons.group,
                  hintText: 'Select Section',
                  onChanged: (v) => setState(() => _sectionValue = v),
                ),
                const SizedBox(height: 16),

                // Teacher Search
                _buildSearchableField(
                  label: 'Teacher',
                  value: _teacherValue,
                  items: _teachers,
                  icon: Icons.person,
                  hintText: 'Select Teacher',
                  onChanged: (v) => setState(() => _teacherValue = v),
                ),
                const SizedBox(height: 16),

                // Room No. Search
                _buildSearchableField(
                  label: 'Room No.',
                  value: _roomValue,
                  items: _rooms,
                  icon: Icons.place,
                  hintText: 'Select Room',
                  onChanged: (v) => setState(() => _roomValue = v),
                ),
                const SizedBox(height: 16),

                // Day and Period Selection
                Row(
                  children: [
                    Expanded(
                      child: _buildEnhancedDropdown(
                        label: 'Day',
                        value: _dayValue,
                        items: _days,
                        icon: Icons.calendar_today,
                        hintText: 'Select Day',
                        onChanged: (v) => setState(() => _dayValue = v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildEnhancedDropdown(
                        label: 'Period',
                        value: _periodValue,
                        items: _periods,
                        icon: Icons.access_time,
                        hintText: 'Select Period',
                        onChanged: (v) => setState(() => _periodValue = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        child: ElevatedButton(
                          onPressed: _onShowPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                            shadowColor: Colors.blue.withOpacity(0.3),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.visibility, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Show Timetable',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required String hintText,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey.shade50,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.blue),
              iconSize: 24,
              elevation: 8,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  hintText,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              onChanged: onChanged,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                );
              }).toList(),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              menuMaxHeight: 300,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchableField({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required String hintText,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showSearchDialog(label, items, onChanged),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
              color: Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? hintText,
                    style: TextStyle(
                      fontSize: 14,
                      color: value != null ? Colors.black87 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.search, color: Colors.blue.shade600, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSearchDialog(String label, List<String> items, ValueChanged<String?> onChanged) {
    TextEditingController searchController = TextEditingController();
    List<String> filteredItems = List.from(items);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search $label',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Type to search...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setState(() => filteredItems = List.from(items));
                              },
                            )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          autofocus: true,
                          onChanged: (value) {
                            setState(() {
                              filteredItems = items
                                  .where((item) => item.toLowerCase().contains(value.toLowerCase()))
                                  .toList();
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${filteredItems.length} results found',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No results found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try a different search term',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return ListTile(
                          title: Text(
                            item,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () {
                            onChanged(item);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _autoFillFromProfile() async {
    if (_userClassName == null || _userSemester == null) {
      await _loadUserProfile();
    }

    setState(() {
      if (_userClassName != null) {
        _classValue = _classes.firstWhere(
              (cls) => cls.contains(_userClassName!) || _userClassName!.contains(cls),
          orElse: () => _userClassName!,
        );
      }
      if (_userSemester != null) {
        _semesterValue = _userSemester;
      }
    });

    _showSnackBar('Auto-filled from profile', Colors.green);
  }

  void _fillPopularData() {
    setState(() {
      _classValue = 'B.Sc. (Physical Science Hons) Physics';
      _semesterValue = 'II';
      _sectionValue = 'A';
    });
    _showSnackBar('Popular data filled', Colors.purple);
  }

  void _onShowPressed() {
    if (_classValue == null || _semesterValue == null) {
      _showSnackBar('Please select Class and Semester', Colors.red);
      return;
    }

    // Navigate to web view
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => TimetableWebScreen(
          url: 'http://slc.collegett.in/',
          className: _classValue,
          semester: _semesterValue,
          section: _sectionValue,
          teacher: _teacherValue,
          room: _roomValue,
          day: _dayValue,
          period: _periodValue,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _onClearFilters() {
    setState(() {
      _classValue = null;
      _semesterValue = null;
      _sectionValue = null;
      _teacherValue = null;
      _roomValue = null;
      _dayValue = null;
      _periodValue = null;
    });
    _showSnackBar('All filters cleared', Colors.blue);
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}