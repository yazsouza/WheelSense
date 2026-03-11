import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'esp32_service.dart';

void main() {
  runApp(const WheelProApp());
}

class WheelProApp extends StatelessWidget {
  const WheelProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
          primary: Colors.blue.shade900,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, color: Colors.black),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<SessionResult> _history = [];
  int _testDuration = 10;

  @override
  Widget build(BuildContext context) {
    final screens = [
      ProDashboard(
        duration: _testDuration,
        onResult: (res) => setState(() => _history.insert(0, res)),
      ),
      ProgressScreen(history: _history),
      SettingsScreen(
        duration: _testDuration,
        onDurationChanged: (v) => setState(() => _testDuration = v),
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.blue.shade900,
        unselectedItemColor: Colors.grey.shade600,
        backgroundColor: Colors.grey.shade100,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt, size: 28),
            label: "Test",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history, size: 28),
            label: "History",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings, size: 28),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}

// ===================== DASHBOARD =====================

class ProDashboard extends StatefulWidget {
  final int duration;
  final Function(SessionResult) onResult;

  const ProDashboard({
    super.key,
    required this.onResult,
    required this.duration,
  });

  @override
  State<ProDashboard> createState() => _ProDashboardState();
}

class _ProDashboardState extends State<ProDashboard> {
  final Esp32Service esp = Esp32Service();

  StreamSubscription<WheelData>? _espSub;
  Timer? _countdownTimer;
  Timer? _testTimer;

  Maneuver? selectedManeuver;
  int countdown = 0;
  int timerLeft = 0;
  bool isTesting = false;
  int? lastScore;
  List<WheelData> sessionData = [];

  WheelData currentData = WheelData.empty;

  final List<Maneuver> maneuvers = [
    Maneuver(
      name: "Straight Line",
      steps: [
        ManeuverStep(
          text: "Lean slightly forward to increase stability.",
          imagePath: "assets/images/wheeling_forward.png",
        ),
        ManeuverStep(
          text: "Use long, smooth strokes between 11 and 2 o'clock.",
        ),
        ManeuverStep(
          text: "Keep your head up and look 5 meters ahead.",
        ),
      ],
    ),
    Maneuver(
      name: "360° Pivot",
      isPivot: true,
      steps: [
        ManeuverStep(
          text: "Push one wheel forward while pulling the other backward.",
          imagePath: "assets/images/wheeling_on_spot.png",
        ),
        ManeuverStep(
          text: "Move hands at the same time in opposite directions.",
        ),
        ManeuverStep(
          text: "Keep the wheelchair within its own length.",
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();

    esp.start();

    _espSub = esp.stream.listen((data) {
      if (!mounted) return;

      setState(() {
        currentData = data;
        if (isTesting) {
          sessionData.add(data);
        }
      });
    });
  }

  @override
  void dispose() {
    _espSub?.cancel();
    _countdownTimer?.cancel();
    _testTimer?.cancel();
    esp.dispose();
    super.dispose();
  }

  void startSequence() {
    if (selectedManeuver == null) return;

    _countdownTimer?.cancel();
    _testTimer?.cancel();

    setState(() {
      countdown = 3;
      lastScore = null;
      sessionData.clear();
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      if (countdown > 1) {
        setState(() => countdown--);
      } else {
        t.cancel();
        runTest();
      }
    });
  }

  void runTest() {
    setState(() {
      countdown = 0;
      isTesting = true;
      timerLeft = widget.duration;
      sessionData.clear();
    });

    _testTimer?.cancel();
    _testTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      if (timerLeft > 1) {
        setState(() => timerLeft--);
      } else {
        t.cancel();
        finishTest();
      }
    });
  }

  void finishTest() {
    double scoreValue = 0;

    if (sessionData.isNotEmpty && selectedManeuver != null) {
      if (selectedManeuver!.isPivot) {
        final avgPivotBalance = sessionData
                .map((d) => (d.signedL + d.signedR).abs())
                .reduce((a, b) => a + b) /
            sessionData.length;

        scoreValue = (100 - (avgPivotBalance * 5)).clamp(0, 100);
      } else {
        final avgDrift = sessionData
                .map((d) => d.rpmDiff)
                .reduce((a, b) => a + b) /
            sessionData.length;

        scoreValue = (100 - (avgDrift * 6)).clamp(0, 100);
      }
    }

    widget.onResult(
      SessionResult(
        selectedManeuver!.name,
        scoreValue.toInt(),
        DateTime.now(),
      ),
    );

    setState(() {
      isTesting = false;
      timerLeft = 0;
      lastScore = scoreValue.toInt();
    });
  }

  @override
  Widget build(BuildContext context) {
    final WheelData d = currentData;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (countdown > 0)
                _buildCountdown()
              else if (isTesting)
                _buildActiveTest(d)
              else if (lastScore != null)
                _buildResultView()
              else
                _buildSelectionView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return Text(
      "$countdown",
      style: TextStyle(
        fontSize: 160,
        fontWeight: FontWeight.bold,
        color: Colors.blue.shade900,
      ),
    );
  }

  Widget _buildActiveTest(WheelData d) {
    return Column(
      children: [
        Text(
          "${timerLeft}s",
          style: const TextStyle(
            fontSize: 80,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          selectedManeuver?.name ?? "",
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.2,
          children: [
            _tile("Left RPM", d.rpmL.toStringAsFixed(1)),
            _tile("Right RPM", d.rpmR.toStringAsFixed(1)),
            _tile("Left Dir", d.dirL),
            _tile("Right Dir", d.dirR),
            _tile("Speed m/s", d.speedMS.toStringAsFixed(2)),
            _tile("Difference", d.rpmDiff.toStringAsFixed(1)),
            _tile("Motion", d.motion),
            _tile(
              "Connection",
              d.motion == "Disconnected" ? "Lost" : "Live",
            ),
          ],
        ),
      ],
    );
  }

  Widget _tile(String label, String value) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView() {
    return Column(
      children: [
        const Text(
          "SCORE",
          style: TextStyle(fontSize: 20, letterSpacing: 2),
        ),
        Text(
          "$lastScore%",
          style: TextStyle(
            fontSize: 140,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: 200,
          height: 60,
          child: ElevatedButton(
            onPressed: () => setState(() => lastScore = null),
            child: const Text(
              "FINISH",
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionView() {
    return Column(
      children: [
        const Text(
          "SELECT TRIAL",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ...maneuvers.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: selectedManeuver == m
                  ? Colors.blue.shade100
                  : Colors.grey.shade100,
              title: Text(
                m.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => setState(() => selectedManeuver = m),
            ),
          ),
        ),
        if (selectedManeuver != null) _buildInstructions(),
      ],
    );
  }

  Widget _buildInstructions() {
    final primaryStep = selectedManeuver!.steps.firstWhere(
      (s) => s.imagePath != null,
      orElse: () => selectedManeuver!.steps.first,
    );

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          if (primaryStep.imagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.asset(
                  primaryStep.imagePath!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Text(
            selectedManeuver!.steps.map((s) => "• ${s.text}").join("\n\n"),
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: startSequence,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade900,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                "START TRIAL",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== HISTORY =====================

class ProgressScreen extends StatelessWidget {
  final List<SessionResult> history;

  const ProgressScreen({
    super.key,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Performance History"),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: history.isEmpty
          ? const Center(child: Text("No trials recorded yet."))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final res = history[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade900,
                    child: Text(
                      "${res.score}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  title: Text(
                    res.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    DateFormat('MMM d, yyyy • HH:mm').format(res.date),
                  ),
                );
              },
            ),
    );
  }
}

// ===================== SETTINGS =====================

class SettingsScreen extends StatelessWidget {
  final int duration;
  final Function(int) onDurationChanged;

  const SettingsScreen({
    super.key,
    required this.duration,
    required this.onDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            "Test Configuration",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text("Sensing Duration: $duration seconds"),
          Slider(
            value: duration.toDouble(),
            min: 5,
            max: 20,
            divisions: 3,
            onChanged: (v) => onDurationChanged(v.toInt()),
          ),
          const SizedBox(height: 20),
          const Text(
            "This app uses live ESP32 data only.",
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}