// lib/maneuvers/forward_straight.dart
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
    List<String> feedback = [];
    
    double avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    double avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;

    if (avgSpeed < 0.05) return TestEvaluation(20, ['Minimal movement detected.']);

    // 1. DRIFT ANALYSIS
    if (avgAbsYawRate > 2.0) { 
      score -= (avgAbsYawRate * 2.5); 
      if (avgYawRate > 1.5) {
        feedback.add('Drifted left (avg ${avgAbsYawRate.toStringAsFixed(1)} deg/s). Push harder on left wheel.');
      } else if (avgYawRate < -1.5) {
        feedback.add('Drifted right (avg ${avgAbsYawRate.toStringAsFixed(1)} deg/s). Push harder on right wheel.');
      } else {
        feedback.add('Wobbled back and forth. Keep pushes symmetrical.');
      }
    } else {
      feedback.add('Excellent directional control. No drift detected.');
    }

    // 2. CONSTANT SPEED ANALYSIS
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
        feedback.add('Great steady cruising speed of ${midAvgSpeed.toStringAsFixed(2)} m/s.');
      }
    }
    
    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);