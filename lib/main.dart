import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'esp32_service.dart';
import 'models.dart';
import 'maneuvers/all_maneuvers.dart';
import 'widgets/live_overview_section.dart';

enum HistoryTimeframe { today, week, month, allTime }

void main() {
  runApp(const WheelPrettyApp());
}

class WheelPrettyApp extends StatelessWidget {
  const WheelPrettyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WheelSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        cardTheme: CardThemeData(
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Esp32Service esp;

  int _currentIndex = 0;
  
  // --- USER PROFILE STATE ---
  String userName = "User";
  int selectedAvatarIndex = 0;
  
  // default.png is index 0. The settings menu will skip it and only show indices 1, 2, and 3.
  final List<String> avatarImages = [
    'assets/icons/default.png',
    'assets/icons/toopie.png', 
    'assets/icons/naila.png', 
    'assets/icons/biscuit.png'
  ];
  
  final TextEditingController _nameController = TextEditingController();

  bool demoMode = false;
  bool unlockAllLevels = false;
  String baseUrl = 'http://192.168.4.1';
  int pollingMs = 150; 
  int testDurationSetting = 10;

  bool connected = false;
  final ValueNotifier<WheelData> liveWheelData = ValueNotifier(WheelData.empty());
  Timer? _pollTimer;

  Timer? _sessionTimer;
  Timer? _countdownTimer;

  Duration sessionRemaining = Duration.zero;
  bool sessionRunning = false;
  bool isCountingDown = false;
  int countdownValue = 3;
  List<WheelData> _sessionDataPool = [];

  Maneuver? selectedManeuver;
  ExpansionTileController? _expandedTileController;

  final List<SessionResult> sessionHistory = [];
  HistoryTimeframe _selectedHistoryTimeframe = HistoryTimeframe.today;

  final maneuvers = appManeuvers;
  final ScrollController _trainingScrollController = ScrollController();

@override
  void initState() {
    super.initState();
    esp = Esp32Service(baseUrl: baseUrl);
    _loadSavedData();
    _startPolling();

    // ADDED: Trigger the safety pop-up right after the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSafetyDisclaimer();
    });
  }

  // ADDED: The Safety Disclaimer Dialog function
  void _showSafetyDisclaimer() {
    showDialog(
      context: context,
      barrierDismissible: false, // Forces the user to click the "I Agree" button to dismiss
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Safety First', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WheelSense is designed to supplement - not replace - clinical demonstration and training.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Practicing wheelchair skills without prior training, in an unsafe environment, or without necessary safety equipment (such as a spotter strap) can result in serious injury. Do not attempt these skills without clinical support.',
              ),
              SizedBox(height: 12),
              Text(
                'By continuing, you acknowledge that you understand the risks associated with practicing wheelchair maneuvers and have consulted with a clinician.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('I Understand and Agree'),
          ),
        ],
      ),
    );
  }
// Helper function to open web links
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $urlString')),
      );
    }
  }
  @override
  void dispose() {
    _pollTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    _trainingScrollController.dispose();
    _nameController.dispose();
    liveWheelData.dispose(); //added to lower stress on main
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName') ?? "User";
      _nameController.text = userName == "User" ? "" : userName;
      
      selectedAvatarIndex = prefs.getInt('selectedAvatarIndex') ?? 0;
      unlockAllLevels = prefs.getBool('unlockAllLevels') ?? false;
      testDurationSetting = prefs.getInt('testDurationSetting') ?? 10;

      final historyJsonList = prefs.getStringList('sessionHistory');
      if (historyJsonList != null) {
        sessionHistory.clear();
        for (var item in historyJsonList) {
          try {
            final map = jsonDecode(item);
            sessionHistory.add(SessionResult(
              name: map['name'],
              score: map['score'],
              date: DateTime.parse(map['date']),
              duration: Duration(seconds: map['duration']),
              feedback: List<String>.from(map['feedback']),
            ));
          } catch (e) {
            debugPrint("Failed to load a history item: $e");
          }
        }
      }
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', userName);
    await prefs.setInt('selectedAvatarIndex', selectedAvatarIndex);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('unlockAllLevels', unlockAllLevels);
    await prefs.setInt('testDurationSetting', testDurationSetting);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyStrings = sessionHistory.map((r) => jsonEncode({
      'name': r.name,
      'score': r.score,
      'date': r.date.toIso8601String(),
      'duration': r.duration.inSeconds,
      'feedback': r.feedback,
    })).toList();
    await prefs.setStringList('sessionHistory', historyStrings);
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Account?', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to permanently delete all your training data and reset your profile? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                sessionHistory.clear();
                userName = "User";
                _nameController.clear();
                selectedAvatarIndex = 0; 
              });
              
              _saveHistory();
              _saveProfile();
              
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account reset successfully.')),
              );
            },
            child: const Text('Yes, Reset'),
          ),
        ],
      ),
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _fetchData();
    _pollTimer = Timer.periodic(
      Duration(milliseconds: pollingMs),
      (_) => _fetchData(),
    );
  }

Future<void> _fetchData() async {
    if (demoMode) {
      if (!mounted) return;
      
      // Only setState if connection status changed
      if (!connected) setState(() => connected = true);
      
      liveWheelData.value = WheelData.empty();
      
      if (sessionRunning && !isCountingDown) {
        _sessionDataPool.add(liveWheelData.value);
      }
      return;
    }

    try {
      final fresh = await esp.fetchWheelData();
      if (!mounted) return;

      // Only setState if connection status changed from false -> true
      if (!connected) {
        setState(() => connected = true);
      }

      // Update the UI silently without a full screen rebuild
      liveWheelData.value = fresh;

      if (sessionRunning && !isCountingDown) {
        _sessionDataPool.add(fresh);
      }
    } catch (_) {
      if (!mounted) return;
      
      // Only setState if connection status changed from true -> false
      if (connected) {
        setState(() => connected = false);
      }
    }
  }

  void _initiateTest(Maneuver maneuver) {
    if (_trainingScrollController.hasClients) {
      _trainingScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }

    // Collapse the currently open accordion tile
    _expandedTileController?.collapse();
    _expandedTileController = null;

    setState(() {
      selectedManeuver = maneuver;
      isCountingDown = true;
      countdownValue = 3;
      sessionRunning = false;
      sessionRemaining = Duration(seconds: testDurationSetting);
      _sessionDataPool.clear();
    });
    
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        countdownValue--;
        if (countdownValue <= 0) {
          timer.cancel();
          _beginSensing();
        }
      });
    });
  }

  void _beginSensing() {
    setState(() {
      isCountingDown = false;
      sessionRunning = true;
      sessionRemaining = Duration(seconds: testDurationSetting);
    });
    
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        final nextRemaining = sessionRemaining - const Duration(seconds: 1);

        if (nextRemaining.inSeconds <= 0) {
          sessionRemaining = Duration.zero;
          timer.cancel();
          _stopSessionAndScore();
        } else {
          sessionRemaining = nextRemaining;
        }
      });
    });
  }

  void _stopSessionAndScore() {
    _sessionTimer?.cancel();

    if (selectedManeuver != null) {
      if (_sessionDataPool.length < 3) {
        _showErrorDialog(
          "Test Incomplete",
          "Not enough sensor data was captured. Please ensure the ESP32 is connected and try moving a bit slower.",
        );
      } else {
        final evaluation = selectedManeuver!.evaluator(_sessionDataPool);
        
        final result = SessionResult(
          name: selectedManeuver!.name,
          score: evaluation.score,
          date: DateTime.now(),
          duration: Duration(seconds: testDurationSetting),
          feedback: evaluation.feedback,
        );
        
        sessionHistory.insert(0, result);
        _saveHistory();
        _showFeedbackDialog(result);
      }
    }

    setState(() {
      selectedManeuver = null;
      sessionRunning = false;
      sessionRemaining = Duration.zero;
      _sessionDataPool.clear();
    });
  }

  void _cancelTestEarly() {
    _countdownTimer?.cancel();
    _sessionTimer?.cancel();
    setState(() {
      selectedManeuver = null;
      isCountingDown = false;
      sessionRunning = false;
      sessionRemaining = Duration.zero;
      _sessionDataPool.clear();
    });
  }

  List<SessionResult> _getFilteredHistory() {
    final now = DateTime.now();
    return sessionHistory.where((session) {
      final date = session.date;
      switch (_selectedHistoryTimeframe) {
        case HistoryTimeframe.today:
          return date.year == now.year && date.month == now.month && date.day == now.day;
        case HistoryTimeframe.week:
          final startOfToday = DateTime(now.year, now.month, now.day);
          final startOfRange = startOfToday.subtract(const Duration(days: 6));
          final sessionDay = DateTime(date.year, date.month, date.day);
          return !sessionDay.isBefore(startOfRange) && !sessionDay.isAfter(startOfToday);
        case HistoryTimeframe.month:
          return date.year == now.year && date.month == now.month;
        case HistoryTimeframe.allTime:
          return true;
      }
    }).toList();
  }

  String _historyLabel(HistoryTimeframe timeframe) {
    switch (timeframe) {
      case HistoryTimeframe.today: return 'Today';
      case HistoryTimeframe.week: return 'Week';
      case HistoryTimeframe.month: return 'Month';
      case HistoryTimeframe.allTime: return 'All Time';
    }
  }

  Duration _getTotalHistoryDuration(List<SessionResult> sessions) {
    Duration total = Duration.zero;
    for (final session in sessions) {
      total += session.duration;
    }
    return total;
  }

  String _formatSummaryDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final totalMinutes = d.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h';
    return '${minutes}m';
  }

  int _getTotalPracticeSessions() => sessionHistory.length;

  int _getAverageScore() {
    if (sessionHistory.isEmpty) return 0;
    final total = sessionHistory.fold<int>(0, (sum, s) => sum + s.score);
    return (total / sessionHistory.length).round();
  }

  int _getManeuversPracticedCount() {
    final practiced = sessionHistory.map((s) => s.name).toSet();
    return practiced.length;
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _exportHistoryToPhone() async {
    final historyToExport = _getFilteredHistory();

    if (historyToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Date,Time,Test Name,Duration(s),Score,Feedback');

    for (final trip in historyToExport) {
      final dateStr = '${trip.date.year}-${trip.date.month.toString().padLeft(2, '0')}-${trip.date.day.toString().padLeft(2, '0')}';
      final timeStr = '${trip.date.hour.toString().padLeft(2, '0')}:${trip.date.minute.toString().padLeft(2, '0')}';
      final feedbackJoined = trip.feedback.isNotEmpty ? trip.feedback.join(' | ') : 'None';

      buffer.writeln([
        _escapeCsv(dateStr), _escapeCsv(timeStr), _escapeCsv(trip.name),
        trip.duration.inSeconds, trip.score, _escapeCsv(feedbackJoined),
      ].join(','));
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final timeframeLabel = _historyLabel(_selectedHistoryTimeframe).toLowerCase().replaceAll(' ', '_');
      final file = File('${dir.path}/wheelchair_history_${timeframeLabel}_$timestamp.csv');

      await file.writeAsString(buffer.toString());
      
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'WheelSense CSV export',
        subject: 'WheelSense CSV export',
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV created on your phone. Use the share sheet to save or send it.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e')));
    }
  }

  String _fmt(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog(SessionResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('${result.name} Complete!', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${result.score}/100',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: result.score >= 80 ? Colors.green : (result.score >= 50 ? Colors.orange : Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Performance Feedback:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...result.feedback.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      f.contains('Excellent') || f.contains('Great') || f.contains('Good') || f.contains('Perfect')
                          ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: f.contains('Excellent') || f.contains('Great') || f.contains('Good') || f.contains('Perfect')
                          ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomePage(),
      _buildTrainingPage(),
      _buildHistoryPage(),
      _buildSettingsPage(),
    ];
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('WheelSense', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (v) => setState(() => _currentIndex = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: 'Training'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    final totalSessions = _getTotalPracticeSessions();
    final averageScore = _getAverageScore();
    final maneuversPracticed = _getManeuversPracticedCount();
    final totalManeuvers = maneuvers.length;

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.indigo.shade600,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    backgroundImage: AssetImage(avatarImages[selectedAvatarIndex]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(fontSize: 16, color: Colors.indigo.shade100),
                        ),
                        Text(
                          userName.isEmpty ? 'User' : userName,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LiveOverviewSection(
            totalSessions: totalSessions,
            averageScore: averageScore,
            maneuversPracticed: maneuversPracticed,
            totalManeuvers: totalManeuvers,
          ),
          const SizedBox(height: 16),
Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              // ADDED: ValueListenableBuilder only redraws this specific column!
              child: ValueListenableBuilder<WheelData>(
                valueListenable: liveWheelData,
                builder: (context, data, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Sensor Data',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      _DataRow(label: 'Speed', value: '${data.speedMS.toStringAsFixed(2)} m/s'),
                      _DataRow(label: 'Encoder Diff', value: data.rpmDiff.toStringAsFixed(2)),
                      _DataRow(label: 'Yaw Rate (Turn)', value: '${data.yawRateDps.toStringAsFixed(2)} deg/s'),
                      _DataRow(label: 'Pitch (Tilt)', value: '${data.pitchDeg.toStringAsFixed(2)} deg'),
                      _DataRow(label: 'Motion', value: data.motion),
                      _DataRow(label: 'IMU State', value: data.imuMotionState),
                      _DataRow(label: 'Right Wheel', value: data.signedR.toStringAsFixed(2)),
                      _DataRow(label: 'Left Wheel', value: data.signedL.toStringAsFixed(2)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showManeuverBottomSheet(Maneuver maneuver) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ManeuverBottomSheet(
        maneuver: maneuver,
        testDurationSetting: testDurationSetting,
        onStart: () {
          Navigator.pop(context); 
          _initiateTest(maneuver); 
        },
      ),
    );
  }

  Widget _buildTrainingPage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ListView(
          controller: _trainingScrollController,
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Training Progression',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            CustomPaint(
              painter: _SkillTreePainter(count: maneuvers.length),
              child: Column(
                children: List.generate(maneuvers.length, (index) {
                  final maneuver = maneuvers[index];

                  int level = 1; 
                  if (index >= 5 && index <= 8) level = 2; 
                  if (index >= 9) level = 3;
                  
                  bool isUnlocked = index == 0 || unlockAllLevels;
                  if (!isUnlocked && index > 0) {
                    final prevName = maneuvers[index - 1].name;
                    isUnlocked = sessionHistory.any((s) => s.name == prevName && s.score >= 80);
                  }

                  bool hasPassed = sessionHistory.any((s) => s.name == maneuver.name && s.score >= 80);
                  double shiftX = 0;
                  if (index % 4 == 1) shiftX = -70;
                  if (index % 4 == 3) shiftX = 70;

                  return Container(
                    height: 145, 
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(shiftX, 0),
                      child: _SkillNode(
                        maneuver: maneuver,
                        isUnlocked: isUnlocked,
                        hasPassed: hasPassed,
                        level: level, 
                        onTap: () {
                          if (isUnlocked) {
                            _showManeuverBottomSheet(maneuver);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🔒 Score 80+ on the previous skill to unlock!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        onExpand: (controller) {
                          if (_expandedTileController != null && _expandedTileController != controller) {
                            _expandedTileController!.collapse();
                          }
                          _expandedTileController = controller;
                        },
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),

        if (selectedManeuver != null)
          Container(
            color: Colors.black.withOpacity(0.7),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Card(
              color: isCountingDown ? const Color.fromARGB(255, 122, 136, 229) : Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Text(
                      selectedManeuver!.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (isCountingDown) ...[
                      const Text('GET READY...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('$countdownValue', style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900)),
                    ] else ...[
                      const Text('SENSING ACTIVE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(height: 10),
                      Text(_fmt(sessionRemaining), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text('remaining', style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: testDurationSetting == 0 ? 0 : sessionRemaining.inSeconds / testDurationSetting,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _cancelTestEarly,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel Test'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryPage() {
    final filteredHistory = _getFilteredHistory();
    final totalSessions = filteredHistory.length;
    final totalDuration = _getTotalHistoryDuration(filteredHistory);
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Test Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            OutlinedButton.icon(onPressed: _exportHistoryToPhone, icon: const Icon(Icons.download), label: const Text('Export CSV')),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: HistoryTimeframe.values.map((timeframe) {
              final selected = _selectedHistoryTimeframe == timeframe;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_historyLabel(timeframe)),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedHistoryTimeframe = timeframe),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _HistoryStatCard(title: 'Total Sessions', value: '$totalSessions')),
            const SizedBox(width: 12),
            Expanded(child: _HistoryStatCard(title: 'Total Time', value: _formatSummaryDuration(totalDuration))),
          ],
        ),
        const SizedBox(height: 16),
        if (filteredHistory.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(32.0), child: Text('No test records for ${_historyLabel(_selectedHistoryTimeframe).toLowerCase()}.')))
        else
          ...filteredHistory.map(
            (trip) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: trip.score >= 80 ? Colors.green.shade100 : (trip.score >= 50 ? Colors.orange.shade100 : Colors.red.shade100),
                  child: Text('${trip.score}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                title: Text(trip.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${trip.date.month}/${trip.date.day} at ${trip.date.hour}:${trip.date.minute.toString().padLeft(2, '0')} • ${_fmt(trip.duration)}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: trip.feedback.map(
                            (f) => Padding(padding: const EdgeInsets.only(bottom: 6.0), child: Text('• $f', style: const TextStyle(fontSize: 14, color: Colors.black87))),
                          ).toList(),
                    ),
                  ),
                ],
               ),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              connected ? Icons.wifi : Icons.wifi_off,
              color: connected ? Colors.green : Colors.red,
              size: 32,
            ),
            title: Text(connected ? 'Hardware Connected' : 'Hardware Disconnected', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('IP: $baseUrl'),
          ),
        ),
        const SizedBox(height: 16),
        
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('User Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Select an Avatar:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(avatarImages.length - 1, (index) {
                    int actualIndex = index + 1; // Start from index 1 to skip 'default.png'
                    bool isSelected = selectedAvatarIndex == actualIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() => selectedAvatarIndex = actualIndex);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.indigo : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.indigo.shade50,
                          backgroundImage: AssetImage(avatarImages[actualIndex]),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        userName = _nameController.text.trim().isEmpty ? "User" : _nameController.text.trim();
                      });
                      _saveProfile();
                      FocusScope.of(context).unfocus();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile saved successfully!')),
                      );
                    },
                    child: const Text('Save Profile'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Testing Parameters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Test Duration (seconds):', style: TextStyle(fontSize: 16)),
                    DropdownButton<int>(
                      value: testDurationSetting,
                      items: [5, 10, 15, 20].map((int value) => 
                        DropdownMenuItem<int>(value: value, child: Text('$value s'))).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() => testDurationSetting = newValue);
                          _saveSettings();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Capstone Demo Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlock All Map Nodes', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: unlockAllLevels,
                  onChanged: (val) {
                    setState(() => unlockAllLevels = val);
                    _saveSettings();
                  },
                ),
                const SizedBox(height: 16),
                const Text('Data Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Reset Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Permanently delete all scores, progression, and profile settings.'),
                  onTap: _confirmClearHistory,
                ),
              ],
            ),
          ),
        ),
        // ADDED: Resources & Safety Card
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.medical_information, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Resources & Safety', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                
                const Text('Clinical Supplement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'This application is not meant to replace clinician demonstration of each skill. It is designed to supplement foundational training by acting as a reference before, during, or between skill practice attempts.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                
                const Text('Liability Disclaimer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'It is the responsibility of the clinician to explain the risks associated with practicing wheelchair skills and to obtain wheeler consent prior to attempting any new skills. Using this resource without prior training, a safe environment, or a spotter can result in serious injury.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                
                const Text('Comprehensive Resources', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'For a comprehensive approach to the theory and practical application of wheelchair skills, please refer to the established clinical guidelines that power our evaluation metrics:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                
                // Links to External Guidelines
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link, color: Colors.blue),
                  title: const Text('More Resources', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                  onTap: () {
                    // Note: To make this open a real browser window, you would add the 'url_launcher' package.
                    _launchURL('https://linktr.ee/wheelchairresources');
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------
// REUSABLE WIDGETS & PAINTERS FOR THE SKILL TREE
// ---------------------------------------------------------

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _HistoryStatCard extends StatelessWidget {
  final String title;
  final String value;
  const _HistoryStatCard({required this.title, required this.value});
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.cyan)),
          ],
        ),
      ),
    );
  }
}

class _SkillNode extends StatelessWidget {
  final Maneuver maneuver;
  final bool isUnlocked;
  final bool hasPassed;
  final int level;
  final VoidCallback onTap;
  final Function(ExpansionTileController)? onExpand;

  const _SkillNode({
    required this.maneuver,
    required this.isUnlocked,
    required this.hasPassed,
    required this.level,
    required this.onTap,
    this.onExpand,
  });
  
  @override
  Widget build(BuildContext context) {
    Color levelColor = Colors.indigo.shade400; 
    if (level == 2) levelColor = Colors.teal.shade500;
    if (level == 3) levelColor = Colors.deepPurple.shade500; 

    Color nodeColor = hasPassed ? Colors.amber.shade500 : (isUnlocked ? levelColor : Colors.grey.shade300);
    IconData icon = hasPassed ? Icons.star_rounded : (isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded);

    BoxShape shape = BoxShape.circle;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: nodeColor,
              shape: shape,
              boxShadow: isUnlocked ? [
                BoxShadow(color: nodeColor.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 6))
              ] : null,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isUnlocked ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: isUnlocked ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : null,
            ),
            child: Text(
              maneuver.name,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isUnlocked ? Colors.black87 : Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillTreePainter extends CustomPainter {
  final int count;
  _SkillTreePainter({required this.count});
  
  @override
  void paint(Canvas canvas, Size size) {
    final double rowHeight = 145.0;
    final double center = size.width / 2;

    final linePaint = Paint()..color = Colors.grey.shade300..strokeWidth = 2;
    
    // We added 'isRight' and 'isBelow' flags so we can customize each line perfectly
    void drawLevelLine(double y, String text, Color textColor, {bool isRight = false, bool isBelow = false}) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(
          color: textColor.withOpacity(0.6), 
          fontWeight: FontWeight.w900, 
          letterSpacing: 3, 
          fontSize: 14
        ),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      
      // Calculate X: If isRight is true, push it to the right edge. Otherwise, lock it to the left.
      double textX = isRight ? (size.width - textPainter.width - 16) : 16.0;
      
      // Calculate Y: If isBelow is true, draw it under the line. Otherwise, draw it above.
      double textY = isBelow ? (y + 6) : (y - textPainter.height - 6);
      
      textPainter.paint(canvas, Offset(textX, textY)); 
    }

    // Apply the custom flags to get the exact layout you want!
    drawLevelLine(10, 'BEGINNER', Colors.indigo.shade400, isRight: false, isBelow: false);
    drawLevelLine(5 * rowHeight, 'INTERMEDIATE', Colors.teal.shade500, isRight: true, isBelow: true);  
    drawLevelLine(9 * rowHeight, 'ADVANCED', Colors.deepPurple.shade500, isRight: false, isBelow: false);
    
    final pathPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    Path path = Path();
    for (int i = 0; i < count; i++) {
      double shiftX = 0;
      if (i % 4 == 1) shiftX = -70;
      if (i % 4 == 3) shiftX = 70;
      double x = center + shiftX;
      double y = (i * rowHeight) + (rowHeight / 2) - 10;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        double prevShiftX = 0;
        if ((i - 1) % 4 == 1) prevShiftX = -70;
        if ((i - 1) % 4 == 3) prevShiftX = 70;
        double prevX = center + prevShiftX;
        double prevY = ((i - 1) * rowHeight) + (rowHeight / 2) - 10;
        
        path.cubicTo(
          prevX, prevY + 65,
          x, y - 65,
          x, y,
        );
      }
    }
    canvas.drawPath(path, pathPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ManeuverBottomSheet extends StatefulWidget {
  final Maneuver maneuver;
  final int testDurationSetting;
  final VoidCallback onStart;
  
  const _ManeuverBottomSheet({
    required this.maneuver,
    required this.testDurationSetting,
    required this.onStart,
  });
  
  @override
  State<_ManeuverBottomSheet> createState() => _ManeuverBottomSheetState();
}

class _ManeuverBottomSheetState extends State<_ManeuverBottomSheet> {
  int currentStepIndex = 0;
  
  @override
  Widget build(BuildContext context) {
    if (currentStepIndex >= widget.maneuver.steps.length) {
      currentStepIndex = 0;
    }
    final step = widget.maneuver.steps[currentStepIndex];
    final isLastStep = currentStepIndex == widget.maneuver.steps.length - 1;
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24, 
        right: 24, 
        top: 24, 
        bottom: MediaQuery.of(context).padding.bottom + 24
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 5,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          Text(widget.maneuver.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Text('Step ${currentStepIndex + 1} of ${widget.maneuver.steps.length}', style: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (step.imagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  step.imagePath!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180, color: Colors.grey.shade200,
                    child: const Center(child: Text('Image not found. Check pubspec.yaml!')),
                  ),
                ),
              ),
            ),
          Text(step.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(step.text, style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: currentStepIndex == 0 ? null : () => setState(() => currentStepIndex--),
                icon: const Icon(Icons.arrow_back), label: const Text('Back'),
              ),
              if (!isLastStep)
                FilledButton.icon(onPressed: () => setState(() => currentStepIndex++), icon: const Icon(Icons.arrow_forward), label: const Text('Next'))
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  onPressed: widget.onStart, icon: const Icon(Icons.play_arrow), label: Text('Start ${widget.testDurationSetting}s Test'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}