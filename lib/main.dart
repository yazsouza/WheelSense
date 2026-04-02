import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

  bool demoMode = false;
  String baseUrl = 'http://192.168.4.1';
  
  // FIX: Lowered polling to 150ms to get more data points and prevent empty list errors
  int pollingMs = 150; 
  int testDurationSetting = 10;

  bool connected = false;
  bool loading = true;
  WheelData wheelData = WheelData.empty();
  Timer? _pollTimer;

  Timer? _sessionTimer;
  Timer? _countdownTimer;

  Duration sessionRemaining = Duration.zero;
  bool sessionRunning = false;
  bool isCountingDown = false;
  int countdownValue = 3;
  List<WheelData> _sessionDataPool = [];

  Maneuver? selectedManeuver;
  final List<SessionResult> sessionHistory = [];
  HistoryTimeframe _selectedHistoryTimeframe = HistoryTimeframe.today;

  final maneuvers = appManeuvers;

  @override
  void initState() {
    super.initState();
    esp = Esp32Service(baseUrl: baseUrl);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
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
      setState(() {
        loading = false;
        connected = true;
        wheelData = WheelData.empty();
        if (sessionRunning && !isCountingDown) {
          _sessionDataPool.add(wheelData);
        }
      });
      return;
    }

    try {
      final fresh = await esp.fetchWheelData();
      if (!mounted) return;

      setState(() {
        wheelData = fresh;
        connected = true;
        loading = false;
        if (sessionRunning && !isCountingDown) {
          _sessionDataPool.add(wheelData);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connected = false;
        loading = false;
      });
    }
  }

  void _initiateTest(Maneuver maneuver) {
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
      // FIX: Safety Gate - Check for minimum data (at least 3 points) to prevent RangeErrors
      if (_sessionDataPool.length < 3) {
        _showErrorDialog(
          "Test Incomplete",
          "Not enough sensor data was captured. Please ensure the ESP32 is connected and try moving a bit slower.",
        );
      } else {
        // Safe to evaluate now
        final evaluation = selectedManeuver!.evaluator(_sessionDataPool);

        final result = SessionResult(
          name: selectedManeuver!.name,
          score: evaluation.score,
          date: DateTime.now(),
          duration: Duration(seconds: testDurationSetting),
          feedback: evaluation.feedback,
        );

        sessionHistory.insert(0, result);
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
          return date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;

        case HistoryTimeframe.week:
          final startOfToday = DateTime(now.year, now.month, now.day);
          final startOfRange = startOfToday.subtract(const Duration(days: 6));
          final sessionDay = DateTime(date.year, date.month, date.day);
          return !sessionDay.isBefore(startOfRange) &&
              !sessionDay.isAfter(startOfToday);

        case HistoryTimeframe.month:
          return date.year == now.year && date.month == now.month;

        case HistoryTimeframe.allTime:
          return true;
      }
    }).toList();
  }

  String _historyLabel(HistoryTimeframe timeframe) {
    switch (timeframe) {
      case HistoryTimeframe.today:
        return 'Today';
      case HistoryTimeframe.week:
        return 'Week';
      case HistoryTimeframe.month:
        return 'Month';
      case HistoryTimeframe.allTime:
        return 'All Time';
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
    if (d.inSeconds < 60) {
      return '${d.inSeconds}s';
    }

    final totalMinutes = d.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    }
    if (hours > 0) {
      return '${hours}h';
    }
    return '${minutes}m';
  }

  int _getTotalPracticeSessions() {
    return sessionHistory.length;
  }

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
      final dateStr =
          '${trip.date.year}-${trip.date.month.toString().padLeft(2, '0')}-${trip.date.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${trip.date.hour.toString().padLeft(2, '0')}:${trip.date.minute.toString().padLeft(2, '0')}';
      final feedbackJoined =
          trip.feedback.isNotEmpty ? trip.feedback.join(' | ') : 'None';

      buffer.writeln(
        [
          _escapeCsv(dateStr),
          _escapeCsv(timeStr),
          _escapeCsv(trip.name),
          trip.duration.inSeconds,
          trip.score,
          _escapeCsv(feedbackJoined),
        ].join(','),
      );
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final timeframeLabel = _historyLabel(_selectedHistoryTimeframe)
          .toLowerCase()
          .replaceAll(' ', '_');
      final file =
          File('${dir.path}/wheelchair_history_${timeframeLabel}_$timestamp.csv');

      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'WheelSense CSV export',
        subject: 'WheelSense CSV export',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'CSV created on your phone. Use the share sheet to save or send it.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export CSV: $e'),
        ),
      );
    }
  }

  String _fmt(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // FIX: Added the error dialog helper function
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
                color: result.score >= 80
                    ? Colors.green
                    : (result.score >= 50 ? Colors.orange : Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Performance Feedback:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...result.feedback.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      f.contains('Excellent') ||
                              f.contains('Great') ||
                              f.contains('Good') ||
                              f.contains('Perfect')
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      color: f.contains('Excellent') ||
                              f.contains('Great') ||
                              f.contains('Good') ||
                              f.contains('Perfect')
                          ? Colors.green
                          : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
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
        title: const Text('WheelSense'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (v) => setState(() => _currentIndex = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Testing',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
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
            child: ListTile(
              leading: Icon(
                connected ? Icons.wifi : Icons.wifi_off,
                color: connected ? Colors.green : Colors.red,
              ),
              title: Text(
                connected ? 'Connected to ESP32' : 'Disconnected',
              ),
              subtitle: Text(baseUrl),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Sensor Data',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _DataRow(
                    label: 'Speed',
                    value: '${wheelData.speedMS.toStringAsFixed(2)} m/s',
                  ),
                  _DataRow(
                    label: 'Encoder Diff',
                    value: wheelData.rpmDiff.toStringAsFixed(2),
                  ),
                  _DataRow(
                    label: 'Yaw Rate (Turn)',
                    value: '${wheelData.yawRateDps.toStringAsFixed(2)} deg/s',
                  ),
                  _DataRow(
                    label: 'Pitch (Tilt)',
                    value: '${wheelData.pitchDeg.toStringAsFixed(2)} deg',
                  ),
                  _DataRow(label: 'Motion', value: wheelData.motion),
                  _DataRow(label: 'IMU State', value: wheelData.imuMotionState),
                  _DataRow(
                    label: 'Right Wheel',
                    value: wheelData.signedR.toStringAsFixed(2),
                  ),
                  _DataRow(
                    label: 'Left Wheel',
                    value: wheelData.signedL.toStringAsFixed(2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (selectedManeuver != null) ...[
          Card(
            color: isCountingDown
                ? const Color.fromARGB(255, 122, 136, 229)
                : Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    selectedManeuver!.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (isCountingDown) ...[
                    const Text(
                      'GET READY...',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '$countdownValue',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'SENSING ACTIVE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fmt(sessionRemaining),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'remaining',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: testDurationSetting == 0
                          ? 0
                          : sessionRemaining.inSeconds / testDurationSetting,
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
          const SizedBox(height: 16),
        ],
        const Text(
          'Select a Maneuver to Test',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final maneuver in maneuvers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _InteractiveManeuverCard(
              maneuver: maneuver,
              isBusy: isCountingDown || sessionRunning,
              testDurationSetting: testDurationSetting,
              onStart: () => _initiateTest(maneuver),
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
            const Text(
              'Test Records',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            OutlinedButton.icon(
              onPressed: _exportHistoryToPhone,
              icon: const Icon(Icons.download),
              label: const Text('Export CSV'),
            ),
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
                  onSelected: (_) {
                    setState(() {
                      _selectedHistoryTimeframe = timeframe;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _HistoryStatCard(
                title: 'Total Sessions',
                value: '$totalSessions',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HistoryStatCard(
                title: 'Total Time',
                value: _formatSummaryDuration(totalDuration),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filteredHistory.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'No test records for ${_historyLabel(_selectedHistoryTimeframe).toLowerCase()}.',
              ),
            ),
          )
        else
          ...filteredHistory.map(
            (trip) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: trip.score >= 80
                      ? Colors.green.shade100
                      : (trip.score >= 50
                          ? Colors.orange.shade100
                          : Colors.red.shade100),
                  child: Text(
                    '${trip.score}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                title: Text(
                  trip.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${trip.date.month}/${trip.date.day} at ${trip.date.hour}:${trip.date.minute.toString().padLeft(2, '0')} • ${_fmt(trip.duration)}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: trip.feedback
                          .map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Text(
                                '• $f',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          )
                          .toList(),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Testing Parameters',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Test Duration (seconds):',
                      style: TextStyle(fontSize: 16),
                    ),
                    DropdownButton<int>(
                      value: testDurationSetting,
                      items: [5, 10, 15, 20].map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value s'),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() => testDurationSetting = newValue);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;

  const _DataRow({
    required this.label,
    required this.value,
  });

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

  const _HistoryStatCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.cyan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveManeuverCard extends StatefulWidget {
  final Maneuver maneuver;
  final bool isBusy;
  final int testDurationSetting;
  final VoidCallback onStart;

  const _InteractiveManeuverCard({
    required this.maneuver,
    required this.isBusy,
    required this.testDurationSetting,
    required this.onStart,
  });

  @override
  State<_InteractiveManeuverCard> createState() =>
      _InteractiveManeuverCardState();
}

class _InteractiveManeuverCardState extends State<_InteractiveManeuverCard> {
  int currentStepIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (currentStepIndex >= widget.maneuver.steps.length) {
      currentStepIndex = 0;
    }
    final step = widget.maneuver.steps[currentStepIndex];
    final isLastStep = currentStepIndex == widget.maneuver.steps.length - 1;

    return Card(
      child: ExpansionTile(
        title: Text(
          widget.maneuver.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Tap to view step-by-step instructions'),
        onExpansionChanged: (expanded) {
          if (!expanded) {
            setState(() => currentStepIndex = 0);
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Step ${currentStepIndex + 1} of ${widget.maneuver.steps.length}',
                  style: TextStyle(
                    color: Colors.indigo.shade400,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                          height: 180,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Text('Image not found. Check pubspec.yaml!'),
                          ),
                        ),
                      ),
                    ),
                  ),
                Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  step.text,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: currentStepIndex == 0
                          ? null
                          : () => setState(() => currentStepIndex--),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                    if (!isLastStep)
                      FilledButton.icon(
                        onPressed: () => setState(() => currentStepIndex++),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                      )
                    else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                        ),
                        onPressed: widget.isBusy ? null : widget.onStart,
                        icon: const Icon(Icons.play_arrow),
                        label:
                            Text('Start ${widget.testDurationSetting}s Test'),
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
}