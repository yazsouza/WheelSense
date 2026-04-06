import '../models.dart';
import '../esp32_service.dart';

final forwardStraightLine = Maneuver(
  name: 'Forward Straight Line',
  type: ManeuverType.forward,
  steps: [
    ManeuverStep(
      title: 'Push',
      text: 'Hands in starting position on handrims at 11 o\'clock. Push hands forward evenly.',
      imagePath: 'assets/images/wheeling_forward1.png',
    ),
    ManeuverStep(
      title: 'Release',
      text: 'Release hands at 2 o\'clock. Return hands to starting position.',
      imagePath: 'assets/images/wheeling_forward2.png',
    ),
    ManeuverStep(
      title: 'Stop',
      text: 'Gently grip handrim at 1 o\'clock.',
      imagePath: 'assets/images/wheeling_forward3.png',
    ),
    ManeuverStep(
      title: 'Repeat & Evaluate',
      text: 'Maintain a steady cruising speed and track a perfectly straight trajectory.',
    ),
  ],
evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);

    double score = 100.0;
    final List<String> feedback = [];

    final avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    final avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    // 1. MINIMAL MOVEMENT (Auto-Score 0)
    if (avgSpeed < 0.05) {
      return TestEvaluation(0, ['Minimal movement detected. Push harder to reach a measurable speed.']);
    }

    // 2. DRIFT & S-SHAPE ANALYSIS (Fixed Sensitivity)
    int directionChanges = 0;
    int? lastSign;
    for (final d in pool) {
      // 3.0 deg/s deadband ignores natural push wobble
      int sign = (d.yawRateDps > 3.0) ? 1 : (d.yawRateDps < -3.0 ? -1 : 0);
      if (sign == 0) continue;
      if (lastSign != null && sign != lastSign) directionChanges++;
      lastSign = sign;
    }

    if (directionChanges >= 3) {
      score -= (directionChanges * 5.0).clamp(0, 20);
      feedback.add('S-shape trajectory detected. Maintain a straight path by pushing evenly.');
    } else if (avgYawRate > 1.5) {
      score -= (avgYawRate * 3.0).clamp(0, 20);
      feedback.add('You drifted left. Push more on the left wheel to straighten out.');
    } else if (avgYawRate < -1.5) {
      score -= (avgYawRate.abs() * 3.0).clamp(0, 20);
      feedback.add('You drifted right. Push more on the right wheel to straighten out.');
    } else {
      feedback.add('Excellent directional control.');
    }

    // 3. ROLLING BACKWARD (Sliding Penalty up to 50 pts)
    const double deadbandRpm = 2.0;
    final wrongWayCount = pool.where((d) => d.signedR < -deadbandRpm || d.signedL < -deadbandRpm).length;
    if (wrongWayCount > 0) {
      double wrongWayPct = wrongWayCount / pool.length;
      score -= (wrongWayPct * 100).clamp(0, 50);
      feedback.add('Detected rolling backward. Minimize roll between pushes.');
    }

    // 4. INCONSISTENT SPEED (Up to 15 pts)
    final startIdx = (pool.length * 0.2).floor();
    final endIdx = (pool.length * 0.8).floor();
    if (endIdx > startIdx && endIdx <= pool.length) {
      final midPool = pool.sublist(startIdx, endIdx);
      final midAvgSpeed = midPool.map((d) => d.speedMS).reduce((a, b) => a + b) / midPool.length;
      double totalDev = 0.0;
      for (final d in midPool) { totalDev += (d.speedMS - midAvgSpeed).abs(); }
      final avgDeviation = totalDev / midPool.length;
      
      if (avgDeviation > 0.08) {
        score -= (avgDeviation * 80).clamp(0, 15);
        feedback.add('Cruising speed varied. Try to keep your forward speed steadier.');
      }
    }

    // 5. TILT SENSITIVITY
    if (maxPitch > 3.5) {
      score -= ((maxPitch - 3.0) * 7.0).clamp(0, 25);
      if (maxPitch > 7.0) {
        feedback.add('Significant tilt detected! Lean forward to keep casters grounded.');
      } else {
        feedback.add('Slight tilt detected. Focus on a stable, forward posture.');
      }
    } 
    
    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  }
);