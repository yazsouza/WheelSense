import '../models.dart';
import 'forward_straight.dart';
import 'backward_straight.dart';
import 'turn_left.dart';
import 'turn_right.dart';
import 'pivot.dart';
import 'up_ramp.dart';
import 'down_ramp.dart';

final List<Maneuver> appManeuvers = [
  forwardStraightLine,
  backwardStraightLine,
  turnLeftManeuver,
  turnRightManeuver,
  pivotManeuver,
  upRampManeuver,      
  downRampManeuver,    
];
