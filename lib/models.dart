import 'esp32_service.dart';

enum ManeuverType { forward, backward, turnLeft, turnRight, pivot, upRamp, downRamp }

class ManeuverStep {
  final String title;
  final String text;
  final String? imagePath;

  ManeuverStep({
    required this.title,
    required this.text,
    this.imagePath,
  });
}

class TestEvaluation {
  final int score;
  final List<String> feedback;

  TestEvaluation(this.score, this.feedback);
}

class SessionResult {
  final String name;
  final int score;
  final DateTime date;
  final Duration duration;
  final List<String> feedback;

  SessionResult({
    required this.name,
    required this.score,
    required this.date,
    required this.duration,
    required this.feedback,
  });
}

class Maneuver {
  final String name;
  final ManeuverType type;
  final List<ManeuverStep> steps;
  final TestEvaluation Function(List<WheelData> dataPool) evaluator;

  Maneuver({
    required this.name,
    required this.type,
    required this.steps,
    required this.evaluator,
  });
}
