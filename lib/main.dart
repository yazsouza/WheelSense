import 'dart:async';
import 'package:flutter/material.dart';
import 'esp32_service.dart';

void main() {
  runApp(const WheelPrettyApp());
}

class ManeuverStep {
  final String text;
  final String? imagePath;

  ManeuverStep({
    required this.text,
    this.imagePath,
  });
}

class Maneuver {
  final String name;
  final List<ManeuverStep> steps;
  final bool isPivot;

  Maneuver({
    required this.name,
    required this.steps,
    this.isPivot = false,
  });
}

class SessionResult {
  final String name;
  final int score;
  final DateTime date;
  final Duration duration;

  SessionResult({
    required this.name,
    required this.score,
    required this.date,
    required this.duration,
  });
}

class WheelPrettyApp extends StatelessWidget {
  const WheelPrettyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = Colors.indigo;

    return MaterialApp(
      title: 'Wheelchair Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
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
  bool sessionReminders = true;
  bool connected = false;
  bool loading = true;

  String baseUrl = 'http://192.168.4.1';
  int pollingMs = 300;

  WheelData wheelData = WheelData.empty();

  Timer? _pollTimer;
  Timer? _sessionTimer;
  Duration sessionElapsed = Duration.zero;
  bool sessionRunning = false;

  Maneuver? selectedManeuver;
  final List<SessionResult> sessionHistory = [];

  final maneuvers = [
    Maneuver(
      name: 'Straight Line',
      steps: [
        ManeuverStep(text: 'Position the wheelchair on level ground.'),
        ManeuverStep(text: 'Begin pushing forward in a straight line.'),
        ManeuverStep(text: 'Keep both wheels moving as evenly as possible.'),
        ManeuverStep(text: 'Try to maintain a smooth, controlled path.'),
      ],
    ),
    Maneuver(
      name: 'Pivot Turn',
      isPivot: true,
      steps: [
        ManeuverStep(text: 'Start from a stopped position.'),
        ManeuverStep(text: 'Push one wheel more than the other to rotate.'),
        ManeuverStep(text: 'Try to pivot in place with control.'),
        ManeuverStep(text: 'Stop once the target turn is completed.'),
      ],
    ),
  ];

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
        wheelData = _demoData();
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connected = false;
        loading = false;
      });
    }
  }

  WheelData _demoData() {
    final seconds = DateTime.now().millisecond / 1000.0;
    final right = 12.0 + (seconds * 2.0);
    final left = 10.0 + (seconds * 1.5);

    return WheelData(
      rpmR: right,
      rpmL: left,
      signedR: right,
      signedL: left,
      speedMS: 0.36,
      rpmDiff: (right - left).abs(),
      motion: 'Straight (Forward)',
      dirR: 'Forward',
      dirL: 'Forward',
      pitchDeg: 3.8,
      slopeText: 'Uphill 3 deg',
      yawRateDps: 7.4,
      yawDeg: 18.0,
      imuTurnDirection: 'Left',
      imuTurnState: 'Turning Left',
      imuHeadingText: '18 deg Left',
      imuMotionState: 'Turning Detected',
    );
  }

  void _startSession(Maneuver maneuver) {
    setState(() {
      selectedManeuver = maneuver;
      sessionRunning = true;
      sessionElapsed = Duration.zero;
    });

    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        sessionElapsed += const Duration(seconds: 1);
      });
    });
  }

  void _pauseSession() {
    _sessionTimer?.cancel();
    setState(() {
      sessionRunning = false;
    });
  }

  void _resumeSession() {
    if (selectedManeuver == null) return;
    setState(() {
      sessionRunning = true;
    });

    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        sessionElapsed += const Duration(seconds: 1);
      });
    });
  }

  void _stopSession() {
    _sessionTimer?.cancel();

    if (selectedManeuver != null) {
      final score = _calculateSessionScore();
      sessionHistory.insert(
        0,
        SessionResult(
          name: selectedManeuver!.name,
          score: score,
          date: DateTime.now(),
          duration: sessionElapsed,
        ),
      );
    }

    setState(() {
      selectedManeuver = null;
      sessionRunning = false;
      sessionElapsed = Duration.zero;
    });
  }

  int _calculateSessionScore() {
    double base = 70;

    if (selectedManeuver?.isPivot == true) {
      if (wheelData.imuTurnState.contains('Turning')) base += 10;
      if (wheelData.yawRateDps.abs() > 4) base += 10;
      if (wheelData.rpmDiff > 2) base += 10;
    } else {
      if (wheelData.motion.contains('Straight')) base += 10;
      if (wheelData.rpmDiff < 3) base += 10;
      if (wheelData.speedMS > 0.05) base += 10;
    }

    return base.clamp(0, 100).round();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _saveSettings() {
    esp = Esp32Service(baseUrl: baseUrl);
    _startPolling();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings updated')),
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
        title: const Text('Wheelchair Monitor'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (v) {
          setState(() => _currentIndex = v);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Training',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Trips',
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
    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ConnectionBanner(
            connected: connected,
            demoMode: demoMode,
            baseUrl: baseUrl,
          ),
          const SizedBox(height: 16),
          _HeroStats(
            speed: wheelData.speedMS,
            motion: wheelData.motion,
            slope: wheelData.slopeText,
            turnState: wheelData.imuTurnState,
          ),
          const SizedBox(height: 16),
          _PrettySection(
            title: 'Encoder Live Data',
            icon: Icons.tire_repair,
            child: Column(
              children: [
                _PrettyRow(label: 'Right Wheel RPM', value: wheelData.rpmR.toStringAsFixed(2)),
                _PrettyRow(label: 'Left Wheel RPM', value: wheelData.rpmL.toStringAsFixed(2)),
                _PrettyRow(label: 'Signed Right RPM', value: wheelData.signedR.toStringAsFixed(2)),
                _PrettyRow(label: 'Signed Left RPM', value: wheelData.signedL.toStringAsFixed(2)),
                _PrettyRow(label: 'Right Direction', value: wheelData.dirR),
                _PrettyRow(label: 'Left Direction', value: wheelData.dirL),
                _PrettyRow(label: 'Vehicle Speed', value: '${wheelData.speedMS.toStringAsFixed(3)} m/s'),
                _PrettyRow(label: 'RPM Difference', value: wheelData.rpmDiff.toStringAsFixed(2)),
                _PrettyRow(label: 'Encoder Motion State', value: wheelData.motion, highlight: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PrettySection(
            title: 'IMU Live Data',
            icon: Icons.sensors,
            child: Column(
              children: [
                _PrettyRow(label: 'Pitch from Boot', value: '${wheelData.pitchDeg.toStringAsFixed(2)}°'),
                _PrettyRow(label: 'Slope State', value: wheelData.slopeText, highlight: true),
                _PrettyRow(label: 'Yaw Rate', value: '${wheelData.yawRateDps.toStringAsFixed(2)} deg/s'),
                _PrettyRow(label: 'Yaw Angle from Start', value: '${wheelData.yawDeg.toStringAsFixed(2)}°'),
                _PrettyRow(label: 'IMU Turn Direction', value: wheelData.imuTurnDirection),
                _PrettyRow(label: 'IMU Turn State', value: wheelData.imuTurnState, highlight: true),
                _PrettyRow(label: 'IMU Heading Change', value: wheelData.imuHeadingText),
                _PrettyRow(label: 'IMU Motion State', value: wheelData.imuMotionState, highlight: true),
              ],
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Training Session',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 30),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Session Timer',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _fmt(sessionElapsed),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedManeuver != null) ...[
                  _TrainingStatusBox(
                    title: selectedManeuver!.name,
                    encoderState: wheelData.motion,
                    imuState: wheelData.imuTurnState,
                    heading: wheelData.imuHeadingText,
                    speed: wheelData.speedMS,
                    rpmDiff: wheelData.rpmDiff,
                    slope: wheelData.slopeText,
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: sessionRunning
                          ? null
                          : () => _startSession(maneuvers[0]),
                      icon: const Icon(Icons.straighten),
                      label: const Text('Start Straight Line'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: sessionRunning
                          ? null
                          : () => _startSession(maneuvers[1]),
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('Start Pivot'),
                    ),
                    OutlinedButton.icon(
                      onPressed: sessionRunning ? _pauseSession : _resumeSession,
                      icon: Icon(sessionRunning ? Icons.pause : Icons.play_arrow),
                      label: Text(sessionRunning ? 'Pause' : 'Resume'),
                    ),
                    OutlinedButton.icon(
                      onPressed: selectedManeuver != null ? _stopSession : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop & Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final maneuver in maneuvers)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _ManeuverCard(maneuver: maneuver),
          ),
      ],
    );
  }

  Widget _buildHistoryPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.route, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sessionHistory.isEmpty
                        ? 'No past trips yet'
                        : '${sessionHistory.length} saved trip/session${sessionHistory.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (sessionHistory.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: const [
                  Icon(Icons.history, size: 44),
                  SizedBox(height: 12),
                  Text(
                    'Complete a Straight Line or Pivot session to see it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else
          ...sessionHistory.map(
            (trip) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PrettyRow(label: 'Score', value: '${trip.score}/100', highlight: true),
                      _PrettyRow(label: 'Duration', value: _fmt(trip.duration)),
                      _PrettyRow(
                        label: 'Date',
                        value:
                            '${trip.date.year}-${trip.date.month.toString().padLeft(2, '0')}-${trip.date.day.toString().padLeft(2, '0')}',
                      ),
                      _PrettyRow(
                        label: 'Time',
                        value:
                            '${trip.date.hour.toString().padLeft(2, '0')}:${trip.date.minute.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    final urlController = TextEditingController(text: baseUrl);
    final pollingController = TextEditingController(text: pollingMs.toString());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Demo Mode'),
                  subtitle: const Text('Show built-in sample data instead of live ESP32 data'),
                  value: demoMode,
                  onChanged: (v) {
                    setState(() {
                      demoMode = v;
                    });
                    _fetchData();
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Session Reminders'),
                  subtitle: const Text('Keep this as a future reminder toggle in your project UI'),
                  value: sessionReminders,
                  onChanged: (v) {
                    setState(() {
                      sessionReminders = v;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESP32 Connection',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'http://192.168.4.1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pollingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Polling interval (ms)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        baseUrl = urlController.text.trim();
                        pollingMs = int.tryParse(pollingController.text.trim()) ?? 300;
                      });
                      _saveSettings();
                    },
                    child: const Text('Save Settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final bool connected;
  final bool demoMode;
  final String baseUrl;

  const _ConnectionBanner({
    required this.connected,
    required this.demoMode,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final good = demoMode || connected;
    final bg = good ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.10);
    final iconColor = good ? Colors.green : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: bg,
              child: Icon(
                good ? Icons.wifi : Icons.wifi_off,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    demoMode
                        ? 'Demo Mode Active'
                        : connected
                            ? 'Connected to ESP32'
                            : 'Disconnected',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    demoMode ? 'Showing sample app data' : baseUrl,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStats extends StatelessWidget {
  final double speed;
  final String motion;
  final String slope;
  final String turnState;

  const _HeroStats({
    required this.speed,
    required this.motion,
    required this.slope,
    required this.turnState,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatBubble(
            title: 'Speed',
            value: '${speed.toStringAsFixed(3)} m/s',
            icon: Icons.speed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatBubble(
            title: 'Motion',
            value: motion,
            icon: Icons.directions_run,
          ),
        ),
      ],
    );
  }
}

class _StatBubble extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatBubble({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrettySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PrettySection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _PrettyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _PrettyRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: 15,
      fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
      color: highlight ? Theme.of(context).colorScheme.primary : Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingStatusBox extends StatelessWidget {
  final String title;
  final String encoderState;
  final String imuState;
  final String heading;
  final double speed;
  final double rpmDiff;
  final String slope;

  const _TrainingStatusBox({
    required this.title,
    required this.encoderState,
    required this.imuState,
    required this.heading,
    required this.speed,
    required this.rpmDiff,
    required this.slope,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Session: $title',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _PrettyRow(label: 'Encoder State', value: encoderState, highlight: true),
          _PrettyRow(label: 'IMU Turn State', value: imuState, highlight: true),
          _PrettyRow(label: 'Heading Change', value: heading),
          _PrettyRow(label: 'Speed', value: '${speed.toStringAsFixed(3)} m/s'),
          _PrettyRow(label: 'RPM Difference', value: rpmDiff.toStringAsFixed(2)),
          _PrettyRow(label: 'Slope', value: slope),
        ],
      ),
    );
  }
}

class _ManeuverCard extends StatelessWidget {
  final Maneuver maneuver;

  const _ManeuverCard({required this.maneuver});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              maneuver.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(
              maneuver.steps.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        maneuver.steps[i].text,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
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