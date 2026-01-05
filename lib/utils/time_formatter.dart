// ============================================================================
// lib/utils/time_formatter.dart
// ============================================================================
class TimeFormatter {
  static String formatTime(double seconds) {
    int minutes = (seconds / 60).floor();
    int secs = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static double parseTimeToSeconds(String time) {
    List<String> parts = time.split(':');
    if (parts.length == 2) {
      int minutes = int.tryParse(parts[0]) ?? 0;
      int seconds = int.tryParse(parts[1]) ?? 0;
      return minutes * 60.0 + seconds;
    }
    return 0.0;
  }

  static String calculateEstimatedTime(
    DateTime? startTime,
    int currentFrame,
    int totalFrames,
  ) {
    if (startTime == null || currentFrame == 0) {
      return 'Calculating...';
    }

    final elapsed = DateTime.now().difference(startTime).inSeconds;
    final avgTimePerFrame = elapsed / currentFrame;
    final remainingFrames = totalFrames - currentFrame;
    final estimatedSecondsLeft = (avgTimePerFrame * remainingFrames).round();

    if (estimatedSecondsLeft < 60) {
      return '$estimatedSecondsLeft seconds remaining';
    } else {
      final minutes = (estimatedSecondsLeft / 60).floor();
      final seconds = estimatedSecondsLeft % 60;
      return '$minutes min $seconds sec remaining';
    }
  }
}
