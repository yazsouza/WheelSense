import '../models.dart';
import '../esp32_service.dart';

final pivotManeuver = Maneuver(
  name: 'Turning on the Spot (Pivot)',
  type: ManeuverType.pivot,
  steps: [
    ManeuverStep(
      title: 'Opposite Forces', 
      text: 'Push forward on one wheel while pulling backward on the other.',
    ),
    ManeuverStep(
      title: 'Center Axis', 
      text: 'Keep the wheelchair centered in its starting footprint. Evaluation Criteria: Wheels must rotate at the exact same speed in opposite directions.',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);
    
    double score = 100.0;
    List<String> feedback = [];
    
    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    
    // In a perfect pivot, Left RPM + Right RPM = 0.
    double avgSymmetryError = pool.map((d) => (d.signedL + d.signedR).abs()).reduce((a, b) => a + b) / pool.length;
    score -= (avgSymmetryError * 5.0);
    
    if (avgSymmetryError > 3.0) {
       feedback.add('Uneven wheel rotation. Ensure one wheel pulls back at the exact speed the other pushes forward.');
    } else {
       feedback.add('Excellent symmetry. You pivoted perfectly on the center axis.');
    }

    if (avgYawRate.abs() < 5.0) {
      score -= 30;
      feedback.add('Low rotation speed detected. Apply more force to both wheels simultaneously to complete the pivot.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);