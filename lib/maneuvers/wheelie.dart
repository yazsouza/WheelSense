import '../models.dart';
import '../esp32_service.dart';

final wheelieManeuver = Maneuver(
  name: 'Holding a Wheelie',
  type: ManeuverType.wheelie,
  steps: [
    ManeuverStep(
      title: 'Set-up',
      text: 'Remove anti-tippers. Secure a spotter strap to the wheelchair axle bar or cross brace. Always have a spotter.',
    ),
    ManeuverStep(
      title: 'Communicate',
      text: 'Wait until your spotter says "Ready" before every attempt. Disclose the risk of a rear tip.',
    ),
    ManeuverStep(
      title: 'Getting into Wheelie',
      text: 'Hands starting at 11 o\'clock. Lean back and firmly push forward to pop up into the wheelie.',
    ),
    ManeuverStep(
      title: 'Holding Wheelie',
      text: 'Find the balance point (hands between 12 and 1 o\'clock). Reactive Balance: If falling back, pull back. If falling forward, push forward. Relax your grip!',
    ),
    ManeuverStep(
      title: 'Landing',
      text: 'Pull back gently on the rear wheels and lean forward to return upright. Try to land the casters softly.',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.length < 10) {
      return TestEvaluation(0, ['Not enough data. Try to hold the test longer.']);
    }

    double score = 100.0;
    final List<String> feedback = [];

    // 1. ISOLATE THE WHEELIE (Pitch Threshold)
    const double wheelieThreshold = 8.0; 
    const double dangerThreshold = 22.0; // Too far back (tip-over risk)

    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);
    final airborneData = pool.where((d) => d.pitchDeg.abs() >= wheelieThreshold).toList();

    // 2. DID THEY POP?
    if (maxPitch < wheelieThreshold) {
      return TestEvaluation(0, [
        'Casters did not lift. Max tilt was ${maxPitch.toStringAsFixed(1)}°. Lean back and give a firm push forward at 11 o\'clock.'
      ]);
    }

    // 3. HANG TIME (Duration)
    // At 150ms polling, 1 data point = 0.15 seconds
    double hangTimeSeconds = airborneData.length * 0.15;

    if (hangTimeSeconds < 1.0) {
      score -= 40;
      feedback.add('Wheelie held for ${hangTimeSeconds.toStringAsFixed(1)}s. Keep practicing finding that balance point!');
    } else if (hangTimeSeconds < 5.0) {
      score -= 15;
      feedback.add('Good pop! Held for ${hangTimeSeconds.toStringAsFixed(1)}s. Your ultimate goal is to hold it for 30 seconds.');
    } else {
      feedback.add('Excellent! Held for ${hangTimeSeconds.toStringAsFixed(1)}s. You are mastering the balance point.');
    }

    // 4. SAFETY WARNING (Tip-Over Risk)
    if (maxPitch >= dangerThreshold) {
      score -= 40;
      feedback.add('SAFETY WARNING: Tilted back ${maxPitch.toStringAsFixed(1)}°. If you feel yourself falling back, pull back on the wheels!');
    }

    // 5. STABILITY / WOBBLE (While airborne)
    if (airborneData.length >= 3) {
      final avgAirbornePitch = airborneData.map((d) => d.pitchDeg.abs()).reduce((a, b) => a + b) / airborneData.length;
      
      double pitchFluctuation = 0;
      for (final d in airborneData) {
        pitchFluctuation += (d.pitchDeg.abs() - avgAirbornePitch).abs();
      }
      final avgWobble = pitchFluctuation / airborneData.length;

      if (avgWobble > 3.0) {
        score -= (avgWobble * 5.0).clamp(0, 20);
        feedback.add('High wobble detected. Remember: a relaxed hand is key. Make smaller, proactive adjustments.');
      } else if (hangTimeSeconds >= 1.0) {
        feedback.add('Great reactive balance. You kept the chair very stable at ${avgAirbornePitch.toStringAsFixed(1)}°.');
      }
    }

    // 6. DRIFTING AWAY
    final avgSpeed = pool.map((d) => d.speedMS.abs()).reduce((a, b) => a + b) / pool.length;
    if (avgSpeed > 0.25) {
      score -= (avgSpeed * 60).clamp(0, 20);
      feedback.add('You rolled quite a bit. Try to lock the wheelie into one stationary spot.');
    }

    // 7. ANTI-SARCASM FILTER
    int finalScore = score.clamp(0, 100).round();
    if (finalScore < 50) {
      feedback.removeWhere((msg) => msg.contains('Excellent') || msg.contains('Great') || msg.contains('Good pop!'));
    }

    return TestEvaluation(finalScore, feedback.take(3).toList());
  },
);