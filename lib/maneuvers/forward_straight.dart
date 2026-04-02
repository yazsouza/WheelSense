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
    final avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;

    // Benchmarks
    final maxYaw = pool.map((d) => d.yawRateDps).reduce((a, b) => a > b ? a : b);
    final minYaw = pool.map((d) => d.yawRateDps).reduce((a, b) => a < b ? a : b);
    
    // FIX: PEAK TILT SENSITIVITY
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    if (avgSpeed < 0.05) {
      return TestEvaluation(20, ['Minimal movement detected. Push harder to reach a measurable speed.']);
    }

    // 1. Drift analysis
    const double driftThreshold = 2.0;
    final driftedLeft = maxYaw > driftThreshold;
    final driftedRight = minYaw < -driftThreshold;

    if (avgAbsYawRate > driftThreshold) {
      score -= (avgAbsYawRate * 2.8);
      if (driftedLeft && driftedRight) {
        feedback.add('You drifted to both sides. Try to keep both pushes more even.');
      } else if (avgYawRate > 1.5) {
        feedback.add('You drifted left. Push a little more evenly.');
      } else if (avgYawRate < -1.5) {
        feedback.add('You drifted right. Push a little more evenly.');
      }
    } else {
      feedback.add('Excellent directional control.');
    }

    // 2. Wrong direction penalty
    const double deadbandRpm = 2.0;
    final wrongWayCount = pool.where((d) => d.signedR < -deadbandRpm || d.signedL < -deadbandRpm).length;
    if (wrongWayCount > (pool.length * 0.15)) {
      score -= 20;
      feedback.add('Detected rolling backward. Minimize roll between pushes.');
    }

    // 3. Constant speed analysis
    final startIdx = (pool.length * 0.2).floor();
    final endIdx = (pool.length * 0.8).floor();
    if (endIdx > startIdx && endIdx <= pool.length) {
      final midPool = pool.sublist(startIdx, endIdx);
      final midAvgSpeed = midPool.map((d) => d.speedMS).reduce((a, b) => a + b) / midPool.length;
      double totalDev = 0.0;
      for (final d in midPool) { totalDev += (d.speedMS - midAvgSpeed).abs(); }
      final avgDeviation = totalDev / midPool.length;

      if (avgDeviation > 0.08) {
        score -= (avgDeviation * 80);
        feedback.add('Cruising speed varied. Try to keep your forward speed steadier.');
      }
    }

    // 4. FIX: TILT SENSITIVITY (Using Max Pitch)
    if (maxPitch > 3.5) {
      score -= ((maxPitch - 3.0) * 7.0).clamp(0, 25);
      if (maxPitch > 7.0) {
        feedback.add('Significant tilt detected! Lean forward to keep casters grounded.');
      } else {
        feedback.add('Slight tilt detected. Focus on a stable, forward posture.');
      }
    } 
    
    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);