import '../models.dart';
import '../esp32_service.dart';

final backwardStraightLine = Maneuver(
  name: 'Backward Straight Line',
  type: ManeuverType.backward,
  steps: [
    ManeuverStep(title: 'Get ready', text: 'Grasp handrim at 1 o\'clock.', imagePath: 'assets/images/wheeling_backward1.png'),
    ManeuverStep(title: 'Shoulder check', text: 'Scan for obstacles in both directions.', imagePath: 'assets/images/wheeling_backward2.png'),
    ManeuverStep(title: 'Pull rear wheels back evenly', text: 'Use short strokes and repeat.', imagePath: 'assets/images/wheeling_backward3.png'),
  ],
evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);

    double score = 100.0;
    final List<String> feedback = [];

    final avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    final avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    // 1. MINIMAL MOVEMENT (Auto-Score 0)
    if (avgSpeed > -0.05 && avgSpeed < 0.05) {
      return TestEvaluation(0, ['Minimal movement detected.']);
    }

    // 2. DRIFT & S-SHAPE ANALYSIS (Fixed left/right physics)
    int directionChanges = 0;
    int? lastSign;
    for (final d in pool) {
      int sign = (d.yawRateDps > 3.0) ? 1 : (d.yawRateDps < -3.0 ? -1 : 0);
      if (sign == 0) continue;
      if (lastSign != null && sign != lastSign) directionChanges++;
      lastSign = sign;
    }

    if (directionChanges >= 3) {
      score -= (directionChanges * 5.0).clamp(0, 24);
      feedback.add('S-shape trajectory detected. Pull back evenly to maintain a straight line.');
    } else if (avgYawRate > 1.5) {
      // Positive Yaw = Nose left, Rear right. Reversing = drifting RIGHT.
      score -= (avgYawRate * 3.0).clamp(0, 20);
      feedback.add('You drifted right while reversing. Pull more on the right wheel to straighten out.');
    } else if (avgYawRate < -1.5) {
      // Negative Yaw = Nose right, Rear left. Reversing = drifting LEFT.
      score -= (avgYawRate.abs() * 3.0).clamp(0, 20);
      feedback.add('You drifted left while reversing. Pull more on the left wheel to straighten out.');
    } else {
      // Added positive reinforcement for a straight push!
      feedback.add('Excellent backward directional control.');
    }

    // 3. ROLLING FORWARD (Sliding Penalty up to 50 pts)
    const double deadbandRpm = 2.0;
    final wrongWayCount = pool.where((d) => d.signedR > deadbandRpm || d.signedL > deadbandRpm).length;
    if (wrongWayCount > 0) {
      double wrongWayPct = wrongWayCount / pool.length;
      score -= (wrongWayPct * 100).clamp(0, 50);
      feedback.add('Detected rolling forward. Keep pulls consistent to move backward.');
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
        feedback.add('Reversing speed varied. Try to keep your backward speed steadier.');
      }
    }

    // 5. TILT SENSITIVITY
    if (maxPitch > 3.5) {
      score -= ((maxPitch - 3.0) * 7.0).clamp(0, 25);
      feedback.add('Wheelchair tilted back while reversing. Lean forward for stability.');
    } 

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  }
);