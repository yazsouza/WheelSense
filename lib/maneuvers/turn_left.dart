import '../models.dart';
import '../esp32_service.dart';

final turnLeftManeuver = Maneuver(
  name: 'Turning Left',
  type: ManeuverType.turnLeft,
  steps: [
    ManeuverStep(
      title: 'Asymmetrical Push', 
      text: 'Push harder on the right wheel to initiate the turn.',
    ),
    ManeuverStep(
      title: 'Follow Through', 
      text: 'Maintain forward momentum while curving left.',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);
    
    double score = 100.0;
    List<String> feedback = [];
    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;

    // Expected Positive Yaw Rate for Left Turn
    if (avgYawRate <= 1.0) {
      score -= 40;
      feedback.add('Did not detect a sufficient left turn. Push harder on the right wheel to rotate the chassis.');
    } else {
      feedback.add('Good left turn rotation detected (${avgYawRate.toStringAsFixed(1)} deg/s average).');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);