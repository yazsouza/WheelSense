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

  factory WheelData.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    String parseStr(dynamic v) => v?.toString() ?? '';

    return WheelData(
      rpmR: parseNum(json['rpmR']),
      rpmL: parseNum(json['rpmL']),
      signedR: parseNum(json['signedR']),
      signedL: parseNum(json['signedL']),
      speedMS: parseNum(json['speed_m_s']),
      rpmDiff: parseNum(json['rpm_diff']),
      motion: parseStr(json['motion']),
      dirR: parseStr(json['dirR']),
      dirL: parseStr(json['dirL']),
      pitchDeg: parseNum(json['pitch_deg']),
      slopeText: parseStr(json['slope_text']),
      yawRateDps: parseNum(json['yaw_rate_dps']),
      yawDeg: parseNum(json['yaw_deg']),
      imuTurnDirection: parseStr(json['imu_turn_direction']),
      imuTurnState: parseStr(json['imu_turn_state']),
      imuHeadingText: parseStr(json['imu_heading_text']),
      imuMotionState: parseStr(json['imu_motion_state']),
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
        .get(Uri.parse('$baseUrl/data'))
        .timeout(const Duration(seconds: 2));

    if (response.statusCode != 200) {
      throw Exception('ESP32 returned status ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return WheelData.fromJson(decoded);
  }
}