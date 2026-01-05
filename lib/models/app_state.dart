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
