import '../models.dart';
import '../esp32_service.dart';

final backwardStraightLine = Maneuver(
  name: 'Backward Straight Line',
  type: ManeuverType.backward,
  steps: [
    ManeuverStep(
      title: 'Get ready',
      text: 'Grasp handrim at 1 o\'clock.',
      imagePath: 'assets/images/wheeling_backward1.png',
    ),
    ManeuverStep(
      title: 'Shoulder check',
      text: 'Scan for obstacles in both directions.',
      imagePath: 'assets/images/wheeling_backward2.png',
    ),
    ManeuverStep(
      title: 'Pull rear wheels back evenly',
      text: 'Use short strokes and repeat.\n\nEvaluation Criteria: Maintain a consistent backward speed (ignoring the start-up and slow-down phases) and hold a straight line without drifting off-course.',
      imagePath: 'assets/images/wheeling_backward3.png',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);
    
    double score = 100.0;
    List<String> feedback = [];
    
    double avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    double avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;

    if (avgSpeed < 0.05) return TestEvaluation(20, ['Minimal movement detected. Pull harder to reach a measurable speed.']);

    // 1. DRIFT ANALYSIS
    if (avgAbsYawRate > 2.0) { 
      score -= (avgAbsYawRate * 2.5); 
      if (avgYawRate > 1.5) {
        feedback.add('Drifted left by an avg of ${avgAbsYawRate.toStringAsFixed(1)} deg/s.');
      } else if (avgYawRate < -1.5) {
        feedback.add('Drifted right by an avg of ${avgAbsYawRate.toStringAsFixed(1)} deg/s.');
      } else {
        feedback.add('Wobbled back and forth (avg ${avgAbsYawRate.toStringAsFixed(1)} deg/s deviation). Try to pull symmetrically.');
      }
    } else {
      feedback.add('Excellent directional control. No significant drift detected.');
    }

    // 2. WRONG DIRECTION PENALTY (Checking for forward rolling)
    double deadbandRpm = 2.0; 
    int wrongWayCount = pool.where((d) => d.signedR > deadbandRpm || d.signedL > deadbandRpm).length;
    if (wrongWayCount > (pool.length * 0.15)) {
      score -= 20;
      feedback.add('Detected forward movement. Try to minimize rolling forward between backward pulls.');
    }

    // 3. CONSTANT SPEED ANALYSIS
    int startIdx = (pool.length * 0.2).floor(); 
    int endIdx = (pool.length * 0.8).floor();   
    if (endIdx > startIdx) {
      var midPool = pool.sublist(startIdx, endIdx);
      double midAvgSpeed = midPool.map((d) => d.speedMS).reduce((a, b) => a + b) / midPool.length;
      
      double totalDeviation = 0.0;
      for (var d in midPool) totalDeviation += (d.speedMS - midAvgSpeed).abs();
      double avgDeviation = totalDeviation / midPool.length;

      if (avgDeviation > 0.08) {
        score -= (avgDeviation * 80); 
        feedback.add('Cruising speed varied (±${avgDeviation.toStringAsFixed(2)} m/s deviation).');
      } else {
        feedback.add('Great job maintaining a steady backward cruising speed.');
      }
    }
    
    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);
