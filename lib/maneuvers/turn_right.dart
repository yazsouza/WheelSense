import '../models.dart';
import '../esp32_service.dart';

final turnRightManeuver = Maneuver(
  name: 'Turning Right',
  type: ManeuverType.turnRight,
  steps: [
    ManeuverStep(
      title: 'Asymmetrical Push', 
      text: 'Push harder on the left wheel to initiate the turn.',
    ),
    ManeuverStep(
      title: 'Follow Through', 
      text: 'Maintain forward momentum while curving right.',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);
    
    double score = 100.0;
    List<String> feedback = [];
    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;

    // Expected Negative Yaw Rate for Right Turn
    if (avgYawRate >= -1.0) {
      score -= 40;
      feedback.add('Did not detect a sufficient right turn. Push harder on the left wheel to rotate the chassis.');
    } else {
      feedback.add('Good right turn rotation detected (${avgYawRate.abs().toStringAsFixed(1)} deg/s average).');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);
