import '../models.dart';
import '../esp32_service.dart';

final pivotManeuver = Maneuver(
  name: 'Turning on the Spot (180° Pivot)',
  type: ManeuverType.pivot,
  steps: [
    ManeuverStep(
      title: 'Get Ready',
      text: 'One hand on handrim at 1 o’clock and other backward on handrim at 11 o’clock. Decide if you are turning Clockwise or Counter-Clockwise.',
      imagePath: 'assets/images/wheeling_on_spot.png',
    ),
    ManeuverStep(
      title: 'Push & Pull',
      text: 'Push one wheel forward while pulling the other wheel backward. Hands move at the same time in opposite directions.',
      imagePath: 'assets/images/wheeling_on_spot.png',
    ),
    ManeuverStep(
      title: 'Repeat & Evaluate',
      text: 'Repeat, as needed, until you have turned all the way around (180 degrees).\n\nEvaluation Criteria: Maintain a steady rotation rhythm, stay in the exact same footprint, and complete a full 180° turn.',
      imagePath: 'assets/images/wheeling_on_spot.png',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    // 1. CRASH PROTECTION & RANGE ERROR FIX
    // Ensure we have enough data to compare points (prevents Invalid Range 0..1..2)
    if (pool.length < 5) {
      return TestEvaluation(0, ['Processing motion data... please ensure you completed the turn.']);
    }

    double score = 100.0;
    final List<String> feedback = [];

    // 2. CUMULATIVE YAW (The Range Error Fix)
    // We use pool.length - 1 so that [i + 1] never exceeds the list size
    double totalRotation = 0;
    for (int i = 0; i < pool.length - 1; i++) {
      double diff = pool[i + 1].yawDeg - pool[i].yawDeg;
      
      // Handle the 360-degree wrap-around jump
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      
      totalRotation += diff;
    }
    
    final turnMagnitude = totalRotation.abs();

    // 3. UPDATED GRADING: Encouraging & Within 5° Tolerance
    if (turnMagnitude >= 175 && turnMagnitude <= 185) {
      // THE PERFECT TURN (Within 5 degrees)
      score = 100; 
      feedback.add('Perfect 180° turn! Excellent precision and control.');
    } else if (turnMagnitude >= 165 && turnMagnitude <= 195) {
      // THE SUCCESSFUL TURN (Acceptable range)
      double deviation = (turnMagnitude - 180).abs();
      score -= (deviation * 0.5); // Very light penalty
      feedback.add('Great job! You completed the 180° turn within an acceptable range (${turnMagnitude.toStringAsFixed(0)}°).');
    } else {
      // OUTSIDE TARGET RANGE
      double deviation = (turnMagnitude - 180).abs();
      score -= (deviation * 0.8); // Moderate penalty
      
      if (turnMagnitude < 165) {
        feedback.add('Turn was a bit short (${turnMagnitude.toStringAsFixed(0)}°). Try rotating just a bit further.');
      } else {
        feedback.add('You turned slightly past the target (${turnMagnitude.toStringAsFixed(0)}°). Try stopping sooner.');
      }
    }

    // 4. FOOTPRINT CONTROL (Drift Penalty - Made more lenient)
    final avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    
    // Increased threshold from 0.1 to 0.2 m/s before penalizing
    if (avgSpeed > 0.20) {
      score -= (avgSpeed * 60); 
      feedback.add('Try to keep the wheelchair tighter in one spot while pivoting.');
    } else {
      feedback.add('Excellent balance! You stayed centered in your footprint.');
    }

    // 5. PEAK TILT / PITCH ANALYSIS (Keep previous fix)
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    if (maxPitch > 5.0) {
      score -= ((maxPitch - 4.5) * 4.0).clamp(0, 15);
      feedback.add('Watch for slight tilting; try to keep your weight centered.');
    } 

    return TestEvaluation(
      score.clamp(0, 100).round(),
      feedback.take(3).toList(),
    );
  },
);