import '../models.dart';
import 'forward_straight.dart';
import 'backward_straight.dart';
import 'turn_left.dart';
import 'turn_right.dart';
import 'pivot.dart';

final List<Maneuver> appManeuvers = [
  forwardStraightLine,
  backwardStraightLine,
  turnLeftManeuver,
  turnRightManeuver,
  pivotManeuver,
];
