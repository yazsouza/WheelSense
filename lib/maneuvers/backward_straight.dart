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
    final avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    
    // FIX: PEAK TILT SENSITIVITY
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    if (avgSpeed < 0.05) return TestEvaluation(20, ['Minimal movement detected.']);

    // 1. Drift analysis
    const double driftThreshold = 1.8;
    if (avgAbsYawRate > driftThreshold) {
      score -= (avgAbsYawRate * 3.0);
      feedback.add('You drifted while reversing. Pull more evenly.');
    }

    // 2. Direction Changes (S-Shape)
    int directionChanges = 0;
    int? lastSign;
    for (final d in pool) {
      int sign = (d.yawRateDps > 2.0) ? 1 : (d.yawRateDps < -2.0 ? -1 : 0);
      if (sign == 0) continue;
      if (lastSign != null && sign != lastSign) directionChanges++;
      lastSign = sign;
    }
    if (directionChanges >= 2) {
      score -= (directionChanges * 8).clamp(0, 24);
      feedback.add('You corrected side to side. Try to avoid an S-shaped path.');
    }

    // 3. FIX: TILT SENSITIVITY
    if (maxPitch > 3.5) {
      score -= ((maxPitch - 3.0) * 7.0).clamp(0, 25);
      feedback.add('Wheelchair tilted back while reversing. Lean forward for stability.');
    } 

    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);