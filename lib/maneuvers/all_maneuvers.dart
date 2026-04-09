// lib/maneuvers/all_maneuvers.dart
import '../models.dart';
import 'forward_straight.dart';
import 'backward_straight.dart';
import 'turn_left.dart';
import 'turn_right.dart';
import 'turn_left_backward.dart';
import 'turn_right_backward.dart';
import 'pivot.dart';
import 'up_ramp.dart';
import 'down_ramp.dart';
import 'wheelie.dart';

final List<Maneuver> appManeuvers = [
  forwardStraightLine,
  backwardStraightLine,
  turnLeftManeuver,
  turnRightManeuver,
  pivotManeuver,  
  turnLeftBackwardManeuver,    // 5: Intermediate (NEW)
  turnRightBackwardManeuver,   // 6: Intermediate (NEW)
  upRampManeuver,      // Intermediate
  downRampManeuver,    // Intermediate
  wheelieManeuver,             // Advanced
];