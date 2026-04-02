// lib/maneuvers/all_maneuvers.dart
import '../models.dart';
import 'forward_straight.dart';
import 'backward_straight.dart';
import 'turn_left.dart';
import 'turn_right.dart';
import 'pivot.dart';
import 'up_ramp.dart';
import 'down_ramp.dart';
import '../esp32_service.dart';
//import 'wheelie.dart';

// Placeholder for the advanced maneuver
final wheelie = Maneuver(
  name: 'Stationary Wheelie',
  type: ManeuverType.pivot, 
  steps: [
    ManeuverStep(
      title: 'Pop & Balance',
      text: 'Pull back slightly then push sharply forward to pop the casters, maintaining your balance point.',
    ),
  ],
  evaluator: (List<WheelData> pool) => TestEvaluation(100, ['Placeholder evaluation complete.']),
);

final List<Maneuver> appManeuvers = [
  forwardStraightLine,
  backwardStraightLine,
  turnLeftManeuver,
  turnRightManeuver,
  pivotManeuver,
  upRampManeuver,      // Intermediate
  downRampManeuver,    // Intermediate
  wheelie, //remove later
 // wheelieManeuver,             // Advanced
];