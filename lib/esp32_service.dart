import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ===================== Data Models =====================

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

  SessionResult(this.name, this.score, this.date);
}

class WheelData {
  final double rpmR;
  final double rpmL;
  final double signedR;
  final double signedL;
  final double speedMS;
  final double rpmDiff;
  final String motion;
  final String dirR;
  final String dirL;

  const WheelData({
    required this.rpmR,
    required this.rpmL,
    required this.signedR,
    required this.signedL,
    required this.speedMS,
    required this.rpmDiff,
    required this.motion,
    required this.dirR,
    required this.dirL,
  });

  static double _parse(dynamic v) => double.tryParse(v.toString()) ?? 0.0;

  factory WheelData.fromJson(Map<String, dynamic> j) {
    return WheelData(
      rpmR: _parse(j['rpmR']),
      rpmL: _parse(j['rpmL']),
      signedR: _parse(j['signedR']),
      signedL: _parse(j['signedL']),
      speedMS: _parse(j['speed_m_s']),
      rpmDiff: _parse(j['rpm_diff']),
      motion: (j['motion'] ?? 'Stopped').toString(),
      dirR: (j['dirR'] ?? 'Stopped').toString(),
      dirL: (j['dirL'] ?? 'Stopped').toString(),
    );
  }

  static const WheelData empty = WheelData(
    rpmR: 0,
    rpmL: 0,
    signedR: 0,
    signedL: 0,
    speedMS: 0,
    rpmDiff: 0,
    motion: "Waiting...",
    dirR: "Stopped",
    dirL: "Stopped",
  );
}

// ===================== ESP32 Service =====================

class Esp32Service {
  final String baseUrl;

  // For real phone on ESP32 Wi-Fi, use:
  // Esp32Service({this.baseUrl = 'http://192.168.4.1'});

  // For Android emulator using your PC proxy, use:
  Esp32Service({this.baseUrl = 'http://10.0.2.2:8080'});

  final StreamController<WheelData> _controller =
      StreamController<WheelData>.broadcast();

  Stream<WheelData> get stream => _controller.stream;

  Timer? _timer;
  bool _isPolling = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      final res = await http
          .get(Uri.parse('$baseUrl/data'))
          .timeout(const Duration(seconds: 2));

      if (res.statusCode == 200) {
        print("RAW DATA FROM ESP32: ${res.body}");
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        _controller.add(WheelData.fromJson(decoded));
      } else {
        _sendZeroData("Server Error ${res.statusCode}");
      }
    } catch (e) {
      print("Connection Error: $e");
      _sendZeroData("Disconnected");
    } finally {
      _isPolling = false;
    }
  }

  void _sendZeroData(String status) {
    _controller.add(
      WheelData(
        rpmR: 0,
        rpmL: 0,
        signedR: 0,
        signedL: 0,
        speedMS: 0,
        rpmDiff: 0,
        motion: status,
        dirR: "Stopped",
        dirL: "Stopped",
      ),
    );
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}