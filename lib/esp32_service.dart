import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

// Data models for the UI
class ManeuverStep {
  final String text;
  final String? imagePath;
  ManeuverStep({required this.text, this.imagePath});
}

class Maneuver {
  final String name;
  final List<ManeuverStep> steps;
  final bool isPivot;
  Maneuver({required this.name, required this.steps, this.isPivot = false});
}

class SessionResult {
  final String name;
  final int score;
  final DateTime date;
  SessionResult(this.name, this.score, this.date);
}

class WheelData {
  final double rpmR, rpmL, speedMS, rpmDiff;
  final String motion;
  final bool isSimulated;

  const WheelData({
    required this.rpmR, required this.rpmL, required this.speedMS,
    required this.rpmDiff, required this.motion, this.isSimulated = false,
  });

  // Bulletproof parser: handles strings, ints, or doubles from the ESP32
  static double _parse(dynamic v) => double.tryParse(v.toString()) ?? 0.0;

  factory WheelData.fromJson(Map<String, dynamic> j) {
    return WheelData(
      rpmR: _parse(j['rpmR']),
      rpmL: _parse(j['rpmL']),
      speedMS: _parse(j['speed_m_s']),
      rpmDiff: _parse(j['rpm_diff']),
      motion: (j['motion'] ?? 'Stopped').toString(),
      isSimulated: false,
    );
  }

  factory WheelData.mock({bool moving = false}) {
    final r = Random();
    double base = moving ? 20.0 : 0.0;
    double l = base + (moving ? r.nextDouble() * 4 : 0);
    double rr = base + (moving ? r.nextDouble() * 4 : 0);
    return WheelData(
      rpmL: l, rpmR: rr, speedMS: (l + rr) * 0.015,
      rpmDiff: (l - rr).abs(), motion: moving ? "Moving" : "Stopped",
      isSimulated: true,
    );
  }
}

class Esp32Service {
  final String baseUrl;
  Esp32Service({this.baseUrl = 'http://192.168.4.1'});

  final StreamController<WheelData> _controller = StreamController<WheelData>.broadcast();
  Stream<WheelData> get stream => _controller.stream;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/data')).timeout(const Duration(milliseconds: 800));
      if (res.statusCode == 200) {
        // DEBUG PRINT: This will show the raw data in your VS Code terminal
        print("RAW DATA FROM ESP32: ${res.body}"); 
        
        _controller.add(WheelData.fromJson(jsonDecode(res.body)));
      } else { 
        _sendZeroData("Server Error ${res.statusCode}"); 
      }
    } catch (e) { 
      _sendZeroData("Disconnected"); 
      print("Connection Error: $e"); 
    }
  }

  void _sendZeroData(String status) {
    _controller.add(WheelData(
      rpmL: 0.0, rpmR: 0.0, rpmDiff: 0.0, speedMS: 0.0, 
      motion: status, isSimulated: false
    ));
  }

  void dispose() { _timer?.cancel(); _controller.close(); }
}