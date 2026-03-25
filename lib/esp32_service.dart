import 'dart:convert';
import 'package:http/http.dart' as http;

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

  final double pitchDeg;
  final String slopeText;
  final double yawRateDps;
  final double yawDeg;
  final String imuTurnDirection;
  final String imuTurnState;
  final String imuHeadingText;
  final String imuMotionState;

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
    required this.pitchDeg,
    required this.slopeText,
    required this.yawRateDps,
    required this.yawDeg,
    required this.imuTurnDirection,
    required this.imuTurnState,
    required this.imuHeadingText,
    required this.imuMotionState,
  });

  static double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static String _parseStr(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static double _signedFromDirection(double rpm, String direction) {
    switch (direction.toLowerCase()) {
      case 'forward':
        return rpm;
      case 'backward':
        return -rpm;
      default:
        return 0.0;
    }
  }

  factory WheelData.fromJson(Map<String, dynamic> json) {
    final rpmR = _parseNum(json['rpmR']);
    final rpmL = _parseNum(json['rpmL']);

    final dirR = _parseStr(json['dirR'], 'Stopped');
    final dirL = _parseStr(json['dirL'], 'Stopped');

    final signedR = json.containsKey('signedR')
        ? _parseNum(json['signedR'])
        : _signedFromDirection(rpmR, dirR);

    final signedL = json.containsKey('signedL')
        ? _parseNum(json['signedL'])
        : _signedFromDirection(rpmL, dirL);

    return WheelData(
      rpmR: rpmR,
      rpmL: rpmL,
      signedR: signedR,
      signedL: signedL,

      // New Arduino keys
      speedMS: json.containsKey('speed_m_s')
          ? _parseNum(json['speed_m_s'])
          : _parseNum(json['speed']),

      rpmDiff: json.containsKey('rpm_diff')
          ? _parseNum(json['rpm_diff'])
          : _parseNum(json['diff']),

      motion: json.containsKey('motion')
          ? _parseStr(json['motion'], 'Stopped')
          : _parseStr(json['turnState'], 'Stopped'),

      dirR: dirR,
      dirL: dirL,

      pitchDeg: json.containsKey('pitch_deg')
          ? _parseNum(json['pitch_deg'])
          : _parseNum(json['pitchDeg']),

      slopeText: json.containsKey('slope_text')
          ? _parseStr(json['slope_text'], 'Level ground')
          : _parseStr(json['slopeText'], 'Level ground'),

      yawRateDps: json.containsKey('yaw_rate_dps')
          ? _parseNum(json['yaw_rate_dps'])
          : _parseNum(json['yawRate']),

      yawDeg: json.containsKey('yaw_deg')
          ? _parseNum(json['yaw_deg'])
          : _parseNum(json['yawDeg']),

      imuTurnDirection: json.containsKey('imu_turn_direction')
          ? _parseStr(json['imu_turn_direction'], 'Straight')
          : _parseStr(json['imuTurnDirection'], 'Straight'),

      imuTurnState: json.containsKey('imu_turn_state')
          ? _parseStr(json['imu_turn_state'], 'Not Turning')
          : _parseStr(json['imuTurnState'], 'Not Turning'),

      imuHeadingText: json.containsKey('imu_heading_text')
          ? _parseStr(
              json['imu_heading_text'],
              'Centered / near start heading',
            )
          : _parseStr(
              json['imuAngleText'],
              'Centered / near start heading',
            ),

      imuMotionState: json.containsKey('imu_motion_state')
          ? _parseStr(json['imu_motion_state'], 'No Turning Detected')
          : _parseStr(json['imuState'], 'No Turning Detected'),
    );
  }

  factory WheelData.empty() {
    return const WheelData(
      rpmR: 0,
      rpmL: 0,
      signedR: 0,
      signedL: 0,
      speedMS: 0,
      rpmDiff: 0,
      motion: 'Stopped',
      dirR: 'Stopped',
      dirL: 'Stopped',
      pitchDeg: 0,
      slopeText: 'Level ground',
      yawRateDps: 0,
      yawDeg: 0,
      imuTurnDirection: 'Straight',
      imuTurnState: 'Not Turning',
      imuHeadingText: 'Centered / near start heading',
      imuMotionState: 'No Turning Detected',
    );
  }
}

class Esp32Service {
  final String baseUrl;

  const Esp32Service({required this.baseUrl});

  Future<WheelData> fetchWheelData() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/data'),
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 3));

    if (response.statusCode != 200) {
      throw Exception('ESP32 returned status ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('ESP32 response was not a JSON object');
    }

    return WheelData.fromJson(decoded);
  }
}