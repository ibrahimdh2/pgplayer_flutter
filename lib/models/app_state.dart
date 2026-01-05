class AppState {
  bool isPlaying;
  double currentTime;
  double totalDuration;
  double playbackSpeed;
  bool showControls;
  String? videoPath;
  String? subtitlePath;
  bool isInitialized;
  bool isScanning;
  double scanProgress;
  int currentFrameNumber;
  int totalFramesToScan;
  int detectedScenesCount;
  bool hardwareAcceleration;
  String selectedDetector;
  double sensitivityThreshold;
  bool autoSkipEnabled;
  int parallelThreads;
  bool showSubtitles;
  Map<String, String> skipTimestamps;
  List<Map<String, dynamic>> detectedScenes;
  DateTime? scanStartTime;

  AppState({
    this.isPlaying = false,
    this.currentTime = 0.0,
    this.totalDuration = 0.0,
    this.playbackSpeed = 1.0,
    this.showControls = true,
    this.videoPath,
    this.subtitlePath,
    this.isInitialized = false,
    this.isScanning = false,
    this.scanProgress = 0.0,
    this.currentFrameNumber = 0,
    this.totalFramesToScan = 0,
    this.detectedScenesCount = 0,
    this.hardwareAcceleration = false,
    this.selectedDetector = 'nudenet',
    this.sensitivityThreshold = 0.6,
    this.autoSkipEnabled = true,
    this.parallelThreads = 4,
    this.showSubtitles = true,
    this.skipTimestamps = const {},
    this.detectedScenes = const [],
    this.scanStartTime,
  });

  AppState copyWith({
    bool? isPlaying,
    double? currentTime,
    double? totalDuration,
    double? playbackSpeed,
    bool? showControls,
    String? videoPath,
    String? subtitlePath,
    bool? isInitialized,
    bool? isScanning,
    double? scanProgress,
    int? currentFrameNumber,
    int? totalFramesToScan,
    int? detectedScenesCount,
    bool? hardwareAcceleration,
    String? selectedDetector,
    double? sensitivityThreshold,
    bool? autoSkipEnabled,
    int? parallelThreads,
    bool? showSubtitles,
    Map<String, String>? skipTimestamps,
    List<Map<String, dynamic>>? detectedScenes,
    DateTime? scanStartTime,
  }) {
    return AppState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentTime: currentTime ?? this.currentTime,
      totalDuration: totalDuration ?? this.totalDuration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      showControls: showControls ?? this.showControls,
      videoPath: videoPath ?? this.videoPath,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      isInitialized: isInitialized ?? this.isInitialized,
      isScanning: isScanning ?? this.isScanning,
      scanProgress: scanProgress ?? this.scanProgress,
      currentFrameNumber: currentFrameNumber ?? this.currentFrameNumber,
      totalFramesToScan: totalFramesToScan ?? this.totalFramesToScan,
      detectedScenesCount: detectedScenesCount ?? this.detectedScenesCount,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      selectedDetector: selectedDetector ?? this.selectedDetector,
      sensitivityThreshold: sensitivityThreshold ?? this.sensitivityThreshold,
      autoSkipEnabled: autoSkipEnabled ?? this.autoSkipEnabled,
      parallelThreads: parallelThreads ?? this.parallelThreads,
      showSubtitles: showSubtitles ?? this.showSubtitles,
      skipTimestamps: skipTimestamps ?? this.skipTimestamps,
      detectedScenes: detectedScenes ?? this.detectedScenes,
      scanStartTime: scanStartTime ?? this.scanStartTime,
    );
  }
}

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
