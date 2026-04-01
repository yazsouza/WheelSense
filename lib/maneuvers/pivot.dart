// lib/maneuvers/pivot.dart
import '../models.dart';
import '../esp32_service.dart';

final pivotManeuver = Maneuver(
  name: 'Turning on the Spot (180° Pivot)',
  type: ManeuverType.pivot,
  steps: [
    ManeuverStep(
      title: 'Get Ready',
      text: 'One hand on handrim at 1 o’clock and other backward on handrim at 11 o’clock. Decide if you are turning Clockwise or Counter-Clockwise.',
      imagePath: 'assets/images/wheeling_on_spot.png', // ADDED IMAGE HERE
    ),
    ManeuverStep(
      title: 'Push & Pull',
      text: 'Push one wheel forward while pulling the other wheel backward. Hands move at the same time in opposite directions.',
      imagePath: 'assets/images/wheeling_on_spot.png',
    ),
    ManeuverStep(
      title: 'Repeat & Evaluate',
      text: 'Repeat, as needed, until you have turned all the way around (180 degrees).\n\nEvaluation Criteria: Maintain a steady rotation rhythm, stay in the exact same footprint without drifting away, and complete a full 180° turn.',
      imagePath: 'assets/images/wheeling_on_spot.png', // ADDED IMAGE HERE
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);
    
    double score = 100.0;
    List<String> feedback = [];
    
    // Overall translation speed (checks if they moved away from the starting spot)
    double avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    
    // 1. 180 DEGREE TURN CHECK & AUTO-DETECT DIRECTION
    // We compare the heading at the very end of the test to the heading at the very start
    double startYaw = pool.first.yawDeg;
    double endYaw = pool.last.yawDeg;
    double netYaw = endYaw - startYaw;
    
    // Auto-detect intent: Positive yaw = Counter-Clockwise (Left). Negative = Clockwise (Right).
    String direction = netYaw > 0 ? "Counter-Clockwise" : "Clockwise";
    double turnMagnitude = netYaw.abs();

    if (turnMagnitude < 140) {
      score -= (180 - turnMagnitude) * 0.6; // Deduct points for falling short
      feedback.add('Incomplete $direction turn. You only rotated ${turnMagnitude.toStringAsFixed(0)}°. Try to complete a full 180° turn.');
    } else if (turnMagnitude > 220) {
      score -= (turnMagnitude - 180) * 0.6; // Deduct points for over-spinning
      feedback.add('Over-rotated $direction turn (${turnMagnitude.toStringAsFixed(0)}°). Try to stop exactly at 180°.');
    } else {
      feedback.add('Great 180° $direction turn! (${turnMagnitude.toStringAsFixed(0)}°)');
    }

    // 2. STAYING IN THE SAME SPOT (Translation Check)
    if (avgSpeed > 0.08) {
      score -= (avgSpeed * 80);
      feedback.add('Drifted from starting position (avg translation speed ${avgSpeed.toStringAsFixed(2)} m/s). Ensure you pull backward exactly as hard as you push forward to stay on the spot.');
    } else {
      feedback.add('Excellent footprint control. You stayed in the same spot.');
    }

    // 3. CONSTANT SPEED (Rotation Rhythm)
    // We look at the absolute yaw rate to see if the turning speed was somewhat constant
    double avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    
    // Calculate deviation from the average turning speed
    double totalYawDeviation = 0.0;
    for (var d in pool) {
      totalYawDeviation += (d.yawRateDps.abs() - avgAbsYawRate).abs();
    }
    double avgYawDeviation = totalYawDeviation / pool.length;

    // Allow some deviation for the "push-and-reset" nature of hands, but penalize highly jerky movement
    if (avgYawDeviation > 12.0) {
      score -= (avgYawDeviation * 1.5);
      feedback.add('Inconsistent turning rhythm (±${avgYawDeviation.toStringAsFixed(0)} deg/s deviation). Try to make your push-and-pull strokes smoother.');
    } else {
      feedback.add('Smooth and consistent rotation speed.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback);
  },
);
