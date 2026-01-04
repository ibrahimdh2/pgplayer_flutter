import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Extract bundled assets on first run

  runApp(const MyApp());
}

/// Helper function to extract a single file from assets
Future<void> _extractFile({
  required String assetPath,
  required String targetPath,
}) async {
  try {
    // Create parent directories if they don't exist
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    // Load asset as bytes
    final ByteData data = await rootBundle.load(assetPath);
    final List<int> bytes = data.buffer.asUint8List();

    // Write to target location
    await targetFile.writeAsBytes(bytes);

    print('Extracted: $assetPath -> $targetPath');
  } catch (e) {
    print('Failed to extract $assetPath: $e');
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: Home());
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final Player player;
  late final VideoController controller;

  bool isPlaying = false;
  double currentTime = 0.0;
  double totalDuration = 0.0;
  double playbackSpeed = 1.0;
  bool showControls = true;
  Timer? hideControlsTimer;
  Timer? skipCheckTimer;
  String? videoPath;
  bool isInitialized = false;
  bool isScanning = false;
  double scanProgress = 0.0;
  int currentFrameNumber = 0;
  int totalFramesToScan = 0;
  double currentScanTimestamp = 0.0;
  int detectedScenesCount = 0;
  bool hardwareAcceleration = false;

  String selectedDetector = 'nudenet';
  double sensitivityThreshold = 0.6;
  bool autoSkipEnabled = true;
  bool _isHovering = false;
  int parallelThreads = 4;

  Map<String, String> skipTimestamps = {};
  List<Map<String, dynamic>> detectedScenes = [];
  DateTime? scanStartTime;
  Timer? progressUpdateTimer;

  @override
  void initState() {
    super.initState();
    player = Player(configuration: PlayerConfiguration(title: 'PGPlayer'));
    _initializeController();

    player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          isPlaying = playing;
        });
      }
    });

    player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          currentTime = position.inMilliseconds / 1000.0;
        });
        checkAndApplySkips();
      }
    });

    player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          totalDuration = duration.inMilliseconds / 1000.0;
        });
      }
    });

    startSkipCheckTimer();
  }

  void _initializeController() {
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: hardwareAcceleration,
      ),
    );
  }

  void _recreateController() async {
    bool wasPlaying = isPlaying;
    Duration currentPosition = player.state.position;
    String? currentPath = videoPath;

    setState(() {
      isInitialized = false;
    });

    _initializeController();

    if (currentPath != null) {
      await player.open(Media(currentPath));
      await player.seek(currentPosition);
      if (wasPlaying) {
        await player.play();
      }

      setState(() {
        isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    hideControlsTimer?.cancel();
    skipCheckTimer?.cancel();
    progressUpdateTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> pickAndLoadVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        await loadVideo(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking video: $e')));
      }
    }
  }

  Future<void> loadVideo(String path) async {
    try {
      await player.open(Media(path));

      setState(() {
        videoPath = path;
        isInitialized = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video loaded successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading video: $e')));
      }
    }
  }

  // Multi-threaded video scanning with Python multiprocessing
  Future<void> scanVideoForNSFW() async {
    if (videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a video first')),
      );
      return;
    }

    setState(() {
      isScanning = true;
      scanProgress = 0.0;
      detectedScenes = [];
      currentFrameNumber = 0;
      detectedScenesCount = 0;
      scanStartTime = DateTime.now();
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final framesDir = Directory('${tempDir.path}/frames');
      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create();

      int intervalSeconds = 2;
      int totalFrames = (totalDuration / intervalSeconds).ceil();

      setState(() {
        totalFramesToScan = totalFrames;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Extracting frames and scanning with $parallelThreads threads...',
          ),
        ),
      );

      // Use extracted ffmpeg from project root
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final ffmpegPath = path.join(
        executableDir,
        'data/flutter_assets/assets/ffmpeg',
        'bin',
        'ffmpeg',
      );

      // Step 1: Extract all frames first
      List<Map<String, dynamic>> frameTasks = [];
      for (int i = 0; i < totalFrames; i++) {
        double timestamp = i * intervalSeconds.toDouble();
        String framePath =
            '${framesDir.path}/frame_${i}_${timestamp.toStringAsFixed(0)}.jpg';
        frameTasks.add({'index': i, 'timestamp': timestamp, 'path': framePath});

        await Process.run(
          "/home/ibrahim/Documents/pgplayer_flutter/assets/ffmpeg/bin/ffmpeg",
          [
            '-ss',
            timestamp.toString(),
            '-i',
            videoPath!,
            '-vframes',
            '1',
            '-q:v',
            '2',
            framePath,
          ],
        );

        setState(() {
          currentFrameNumber = i + 1;
          scanProgress =
              (i + 1) / (totalFrames * 2); // First half is extraction
        });
      }

      // Step 2: Process all frames with Python multiprocessing
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Frame extraction complete. Now analyzing with AI ($parallelThreads threads)...',
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      List<Map<String, dynamic>> results = await _analyzeBatchWithPython(
        frameTasks,
        framesDir.path,
      );

      // Collect NSFW scenes
      for (var result in results) {
        if (result['isNSFW'] == true) {
          detectedScenes.add({
            'timestamp': result['timestamp'],
            'frame': result['index'],
            'path': result['path'],
          });
        }
      }

      setState(() {
        detectedScenesCount = detectedScenes.length;
        scanProgress = 1.0;
      });

      generateSkipTimestamps();

      setState(() {
        isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scan complete! Found ${detectedScenes.length} NSFW scenes',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error scanning video: $e')));
      }
    }
  }

  // Use Python multiprocessing for true parallel AI detection
  Future<List<Map<String, dynamic>>> _analyzeBatchWithPython(
    List<Map<String, dynamic>> frameTasks,
    String framesDir,
  ) async {
    // Use extracted detector.exe from project root
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final pythonExePath = path.join(
      executableDir,
      'data/flutter_assets/assets/',
      'detector',
    );

    final inputJsonPath = '$framesDir/input.json';
    final resultPath = '$framesDir/results.json';
    final progressPath = '$framesDir/progress.txt';

    // Inverted threshold for correct sensitivity
    double actualThreshold = 1.0 - sensitivityThreshold;

    // Create input JSON for the Python executable
    Map<String, dynamic> inputData = {
      'frames': frameTasks,
      'detector': selectedDetector,
      'threshold': actualThreshold,
      'threads': parallelThreads,
      'result_path': resultPath,
      'progress_path': progressPath,
    };

    await File(inputJsonPath).writeAsString(jsonEncode(inputData));

    // Verify input file was created
    if (!await File(inputJsonPath).exists()) {
      throw Exception('Failed to create input JSON file');
    }

    // Start progress monitoring
    _startProgressMonitoring(progressPath, frameTasks.length);

    // Run the standalone Python executable
    print('Running detector: $pythonExePath');
    print('Input JSON: $inputJsonPath');
    print('Output path: $resultPath');

    ProcessResult result = await Process.run(
      "/home/ibrahim/Documents/pgplayer_flutter/assets/detector",
      ['--input', inputJsonPath, '--output', resultPath],
    );

    // Stop progress monitoring
    progressUpdateTimer?.cancel();

    // Print output for debugging
    print('Exit code: ${result.exitCode}');
    print('STDOUT: ${result.stdout}');
    print('STDERR: ${result.stderr}');

    if (result.exitCode != 0) {
      throw Exception(
        'Detector failed with exit code ${result.exitCode}: ${result.stderr}',
      );
    }

    // Read results
    final resultsFile = File(resultPath);
    if (!await resultsFile.exists()) {
      // Check if input file still exists
      final inputExists = await File(inputJsonPath).exists();
      throw Exception(
        'Results file not found at: $resultPath\n'
        'Input file exists: $inputExists\n'
        'Stdout: ${result.stdout}\n'
        'Stderr: ${result.stderr}',
      );
    }

    String jsonContent = await resultsFile.readAsString();

    if (jsonContent.isEmpty) {
      throw Exception('Results file is empty');
    }

    List<dynamic> jsonResults = jsonDecode(jsonContent);

    return jsonResults.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void _startProgressMonitoring(String progressPath, int totalFrames) {
    progressUpdateTimer?.cancel();
    progressUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      try {
        final progressFile = File(progressPath);
        if (await progressFile.exists()) {
          String content = await progressFile.readAsString();
          int processed = int.tryParse(content.trim()) ?? 0;

          if (mounted) {
            setState(() {
              currentFrameNumber = processed;
              // Second half of progress is analysis
              scanProgress = 0.5 + (processed / totalFrames * 0.5);
            });
          }
        }
      } catch (e) {
        // Ignore errors during progress reading
      }
    });
  }

  void generateSkipTimestamps() {
    if (detectedScenes.isEmpty) {
      setState(() {
        skipTimestamps = {};
      });
      return;
    }

    List<List<double>> sceneRanges = [];
    List<double> currentScene = [];

    for (var scene in detectedScenes) {
      double timestamp = scene['timestamp'];

      if (currentScene.isEmpty) {
        currentScene.add(timestamp);
      } else {
        if (timestamp - currentScene.last <= 5) {
          currentScene.add(timestamp);
        } else {
          sceneRanges.add([...currentScene]);
          currentScene = [timestamp];
        }
      }
    }

    if (currentScene.isNotEmpty) {
      sceneRanges.add(currentScene);
    }

    Map<String, String> newSkips = {};
    for (var range in sceneRanges) {
      double start = range.first;
      double end = range.last + 5;

      newSkips[formatTime(start)] = formatTime(end.clamp(0, totalDuration));
    }

    setState(() {
      skipTimestamps = newSkips;
    });
  }

  void startSkipCheckTimer() {
    skipCheckTimer?.cancel();
    skipCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (isPlaying && isInitialized) {
        checkAndApplySkips();
      }
    });
  }

  void checkAndApplySkips() {
    if (!isInitialized) return;

    for (var entry in skipTimestamps.entries) {
      String skipFrom = entry.key;
      String skipTo = entry.value;

      double skipFromSeconds = parseTimeToSeconds(skipFrom);
      double skipToSeconds = parseTimeToSeconds(skipTo);

      if ((currentTime - skipFromSeconds).abs() < 0.5 &&
          currentTime < skipToSeconds) {
        if (autoSkipEnabled) {
          player.seek(Duration(milliseconds: (skipToSeconds * 1000).toInt()));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⏭️ Skipped NSFW scene from $skipFrom to $skipTo',
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ NSFW content detected at $skipFrom'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.orange.shade700,
                action: SnackBarAction(
                  label: 'Skip',
                  textColor: Colors.white,
                  onPressed: () {
                    player.seek(
                      Duration(milliseconds: (skipToSeconds * 1000).toInt()),
                    );
                  },
                ),
              ),
            );
          }
        }
        break;
      }
    }
  }

  double parseTimeToSeconds(String time) {
    List<String> parts = time.split(':');
    if (parts.length == 2) {
      int minutes = int.tryParse(parts[0]) ?? 0;
      int seconds = int.tryParse(parts[1]) ?? 0;
      return minutes * 60.0 + seconds;
    }
    return 0.0;
  }

  String formatTime(double seconds) {
    int minutes = (seconds / 60).floor();
    int secs = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String extractMovieName(String filePath) {
    String filename = filePath.split('/').last.split('\\').last;
    filename = filename.substring(0, filename.lastIndexOf('.'));

    filename = filename
        .replaceAll(RegExp(r'[\(\[]?\d{4}[\)\]]?'), '')
        .replaceAll(
          RegExp(
            r'\b(720p|1080p|2160p|4K|HDR|BluRay|BRRip|WEBRip|WEB-DL|HDTV|DVDRip)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(x264|x265|H264|H265|HEVC|AAC|AC3|DTS)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return filename;
  }

  Future<void> openIMDBParentalGuide() async {
    if (videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a video first')),
      );
      return;
    }

    String movieName = extractMovieName(videoPath!);

    showDialog(
      context: context,
      builder: (context) {
        TextEditingController nameController = TextEditingController(
          text: movieName,
        );

        return AlertDialog(
          title: const Text('Search Movie Parents Guide'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Movie/Show Name:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter movie or show name',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'The name was automatically extracted from the filename. '
                    'You can edit it if needed before searching.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                String searchQuery = nameController.text.trim();

                if (searchQuery.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a movie name')),
                  );
                  return;
                }

                // Create Google search URL for parents guide
                String googleSearchUrl =
                    'https://www.google.com/search?q=${Uri.encodeComponent('$searchQuery Parents Guide')}';

                try {
                  final Uri url = Uri.parse(googleSearchUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Searching Google for Parents Guide...',
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  } else {
                    throw 'Could not launch URL';
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error opening Google: $e')),
                    );
                  }
                }
              },
              child: const Text('Search Google'),
            ),
          ],
        );
      },
    );
  }

  void stepBackward() {
    if (isInitialized) {
      final newPosition = Duration(
        milliseconds: ((currentTime - 10) * 1000)
            .clamp(0, totalDuration * 1000)
            .toInt(),
      );
      player.seek(newPosition);
    }
  }

  void stepForward() {
    if (isInitialized) {
      final newPosition = Duration(
        milliseconds: ((currentTime + 10) * 1000)
            .clamp(0, totalDuration * 1000)
            .toInt(),
      );
      player.seek(newPosition);
    }
  }

  void togglePlayPause() {
    if (!isInitialized) {
      pickAndLoadVideo();
      return;
    }
    player.playOrPause();
  }

  void resetControlsTimer() {
    hideControlsTimer?.cancel();

    if (!showControls) {
      setState(() {
        showControls = true;
      });
    }

    if (isPlaying) {
      hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && isPlaying) {
          setState(() {
            showControls = false;
          });
        }
      });
    }
  }

  void _onMouseMove() {
    if (!_isHovering) {
      _isHovering = true;
      resetControlsTimer();

      Future.delayed(const Duration(milliseconds: 100), () {
        _isHovering = false;
      });
    }
  }

  String _calculateEstimatedTime() {
    if (scanStartTime == null || currentFrameNumber == 0) {
      return 'Calculating...';
    }

    final elapsed = DateTime.now().difference(scanStartTime!).inSeconds;
    final avgTimePerFrame = elapsed / currentFrameNumber;
    final remainingFrames = totalFramesToScan - currentFrameNumber;
    final estimatedSecondsLeft = (avgTimePerFrame * remainingFrames).round();

    if (estimatedSecondsLeft < 60) {
      return '$estimatedSecondsLeft seconds remaining';
    } else {
      final minutes = (estimatedSecondsLeft / 60).floor();
      final seconds = estimatedSecondsLeft % 60;
      return '$minutes min $seconds sec remaining';
    }
  }

  void exportSkipJSON() {
    if (skipTimestamps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No skip timestamps to export')),
      );
      return;
    }

    String jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(skipTimestamps);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Timestamps JSON'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonString,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonString));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              try {
                String? outputPath = await FilePicker.platform.saveFile(
                  dialogTitle: 'Save Skip Timestamps',
                  fileName: 'skip_timestamps.json',
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );

                if (outputPath != null) {
                  await File(outputPath).writeAsString(jsonString);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File saved successfully!')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving file: $e')),
                  );
                }
              }
            },
            child: const Text('Save to File'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void showContextMenu(BuildContext context, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 8,
      items: <PopupMenuEntry<String>>[
        _buildMenuItem(
          'open_video',
          Icons.folder_open,
          'Open Video File',
          pickAndLoadVideo,
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'gpu_acceleration',
          hardwareAcceleration
              ? Icons.check_box
              : Icons.check_box_outline_blank,
          'GPU Acceleration',
          () {
            setState(() {
              hardwareAcceleration = !hardwareAcceleration;
            });

            if (isInitialized) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'GPU Acceleration ${hardwareAcceleration ? 'enabled' : 'disabled'}. Reloading video...',
                  ),
                ),
              );
              _recreateController();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'GPU Acceleration ${hardwareAcceleration ? 'enabled' : 'disabled'}',
                  ),
                ),
              );
            }
          },
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'skip_mode',
          autoSkipEnabled ? Icons.fast_forward : Icons.warning_amber,
          autoSkipEnabled ? 'Mode: Auto-Skip' : 'Mode: Warn Only',
          () => _showSkipModeDialog(context),
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'detector_settings',
          Icons.settings,
          'Detection Settings',
          () => _showDetectorSettingsDialog(context),
        ),
        _buildMenuItem(
          'scan_nsfw',
          Icons.search,
          'Scan for NSFW Scenes',
          scanVideoForNSFW,
        ),
        _buildMenuItem(
          'export_json',
          Icons.download,
          'Export Skip JSON',
          exportSkipJSON,
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'imdb_guide',
          Icons.info_outline,
          'IMDB Parental Guide',
          () => openIMDBParentalGuide(),
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'load_skips',
          Icons.file_upload,
          'Load Skip JSON',
          () => _showLoadSkipsDialog(context),
        ),
        _buildMenuItem(
          'view_skips',
          Icons.list,
          'View Skips',
          () => _showSkipsDialog(context),
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'speed',
          Icons.speed,
          'Speed: ${playbackSpeed}x',
          () => _showSpeedDialog(context),
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          'threads',
          Icons.memory,
          'Threads: $parallelThreads',
          () => _showThreadsDialog(context),
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String text,
    VoidCallback onTap,
  ) {
    return PopupMenuItem<String>(
      value: value,
      onTap: () {
        Future.delayed(Duration.zero, onTap);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 12),
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _showThreadsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Processing Threads'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('More threads = faster scanning (uses more CPU)'),
            const SizedBox(height: 16),
            ...([1, 2, 4, 6, 8].map((threads) {
              return RadioListTile<int>(
                title: Text('$threads ${threads == 1 ? 'Thread' : 'Threads'}'),
                subtitle: Text(
                  threads == 1
                      ? 'Sequential processing'
                      : 'Up to ${threads}x faster',
                ),
                value: threads,
                groupValue: parallelThreads,
                onChanged: (value) {
                  setState(() {
                    parallelThreads = value!;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Using $value threads for scanning'),
                    ),
                  );
                },
              );
            })),
          ],
        ),
      ),
    );
  }

  void _showSkipModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('NSFW Skip Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              title: const Text('Auto-Skip'),
              subtitle: const Text('Automatically skip NSFW scenes'),
              value: true,
              groupValue: autoSkipEnabled,
              onChanged: (value) {
                setState(() {
                  autoSkipEnabled = value!;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value! ? '✅ Auto-skip enabled' : '⚠️ Warn mode enabled',
                    ),
                  ),
                );
              },
            ),
            RadioListTile<bool>(
              title: const Text('Warn Only'),
              subtitle: const Text('Show warning with manual skip option'),
              value: false,
              groupValue: autoSkipEnabled,
              onChanged: (value) {
                setState(() {
                  autoSkipEnabled = value!;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value! ? '✅ Auto-skip enabled' : '⚠️ Warn mode enabled',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetectorSettingsDialog(BuildContext context) {
    String tempDetector = selectedDetector;
    double tempSensitivity = sensitivityThreshold;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('NSFW Detection Settings'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Sensitivity Threshold:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Low', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: tempSensitivity,
                        min: 0.1,
                        max: 0.9,
                        divisions: 16,
                        label: tempSensitivity.toStringAsFixed(2),
                        onChanged: (value) {
                          setDialogState(() {
                            tempSensitivity = value;
                          });
                        },
                      ),
                    ),
                    const Text('High', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Center(
                  child: Text(
                    'Current: ${tempSensitivity.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '✅ FIXED: Higher value = More sensitive (catches more scenes)\n'
                    'Lower value = Less sensitive (only explicit scenes)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  selectedDetector = tempDetector;
                  sensitivityThreshold = tempSensitivity;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Using ${tempDetector.toUpperCase()} with sensitivity ${tempSensitivity.toStringAsFixed(2)}',
                    ),
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoadSkipsDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: jsonEncode(skipTimestamps),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Skip Timestamps JSON'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Format: {"1:02": "1:45", "2:30": "3:00"}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter JSON here',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['json'],
                              dialogTitle: 'Select Skip Timestamps JSON',
                            );

                        if (result != null &&
                            result.files.single.path != null) {
                          String path = result.files.single.path!;
                          String content = await File(path).readAsString();
                          controller.text = content;
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error loading file: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Load from File'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              try {
                Map<String, dynamic> decoded = jsonDecode(controller.text);
                setState(() {
                  skipTimestamps = decoded.map(
                    (key, value) => MapEntry(key, value.toString()),
                  );
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Skip timestamps loaded!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Invalid JSON: $e')));
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showSkipsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Active Skip Timestamps'),
        content: SizedBox(
          width: 300,
          child: skipTimestamps.isEmpty
              ? const Text('No skip timestamps configured')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: skipTimestamps.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 16),
                            const SizedBox(width: 8),
                            Text(entry.value),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playback Speed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return RadioListTile<double>(
              title: Text('${speed}x'),
              value: speed,
              groupValue: playbackSpeed,
              onChanged: (value) {
                setState(() {
                  playbackSpeed = value!;
                  player.setRate(playbackSpeed);
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildPlayer(),
          if (isScanning)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color.fromARGB(255, 82, 176, 132),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      scanProgress < 0.5
                          ? 'Extracting frames...'
                          : 'Analyzing with AI ($parallelThreads threads)...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Frame: $currentFrameNumber / $totalFramesToScan',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Using Python multiprocessing with $parallelThreads workers',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Detected scenes: $detectedScenesCount',
                            style: TextStyle(
                              color: detectedScenesCount > 0
                                  ? Colors.orange
                                  : Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 350,
                      child: LinearProgressIndicator(
                        value: scanProgress,
                        backgroundColor: Colors.grey[700],
                        color: const Color.fromARGB(255, 82, 176, 132),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(scanProgress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Estimated time: ${_calculateEstimatedTime()}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      onTap: togglePlayPause,
      onSecondaryTapDown: (details) {
        showContextMenu(context, details.globalPosition);
      },
      child: MouseRegion(
        onHover: (_) => _onMouseMove(),
        child: Stack(
          children: [
            Container(
              color: Colors.black,
              child: Center(
                child: isInitialized
                    ? SizedBox.expand(
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.movie,
                            size: 120,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: pickAndLoadVideo,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Open Video File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(
                                255,
                                82,
                                176,
                                132,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Right-click for menu',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (showControls && isInitialized)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () {
                    final RenderBox renderBox =
                        context.findRenderObject() as RenderBox;
                    final size = renderBox.size;
                    showContextMenu(context, Offset(size.width - 50, 50));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            if (skipTimestamps.isNotEmpty && isInitialized && showControls)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        autoSkipEnabled
                            ? Icons.fast_forward
                            : Icons.warning_amber,
                        size: 16,
                        color: autoSkipEnabled ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${skipTimestamps.length} skip${skipTimestamps.length != 1 ? 's' : ''} (${autoSkipEnabled ? 'auto' : 'warn'})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if ((showControls || !isPlaying) && isInitialized)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildControls()),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                formatTime(currentTime),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (skipTimestamps.isNotEmpty && totalDuration > 0)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: CustomPaint(
                            painter: EnhancedSkipMarkerPainter(
                              skipTimestamps: skipTimestamps,
                              totalDuration: totalDuration,
                              currentTime: currentTime,
                            ),
                          ),
                        ),
                      ),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: currentTime.clamp(0.0, totalDuration),
                        min: 0,
                        max: totalDuration > 0 ? totalDuration : 1,
                        activeColor: const Color.fromARGB(255, 82, 176, 132),
                        inactiveColor: Colors.grey[700],
                        onChanged: (value) {
                          if (isInitialized) {
                            player.seek(
                              Duration(milliseconds: (value * 1000).toInt()),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatTime(totalDuration),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: stepBackward,
                    icon: const Icon(Icons.replay_10),
                    color: Colors.white,
                    iconSize: 28,
                  ),
                  IconButton(
                    onPressed: togglePlayPause,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    color: const Color.fromARGB(255, 82, 176, 132),
                    iconSize: 36,
                  ),
                  IconButton(
                    onPressed: stepForward,
                    icon: const Icon(Icons.forward_10),
                    color: Colors.white,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Speed: ${playbackSpeed}x',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  if (skipTimestamps.isNotEmpty)
                    IconButton(
                      onPressed: () => _showSkipsDialog(context),
                      icon: const Icon(Icons.list),
                      color: Colors.white,
                      tooltip: 'View skips',
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class EnhancedSkipMarkerPainter extends CustomPainter {
  final Map<String, String> skipTimestamps;
  final double totalDuration;
  final double currentTime;

  EnhancedSkipMarkerPainter({
    required this.skipTimestamps,
    required this.totalDuration,
    required this.currentTime,
  });

  double parseTimeToSeconds(String time) {
    List<String> parts = time.split(':');
    if (parts.length == 2) {
      int minutes = int.tryParse(parts[0]) ?? 0;
      int seconds = int.tryParse(parts[1]) ?? 0;
      return minutes * 60.0 + seconds;
    }
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final markerHeight = 12.0;
    final markerTop = (size.height - markerHeight) / 2;

    for (var entry in skipTimestamps.entries) {
      double startSeconds = parseTimeToSeconds(entry.key);
      double endSeconds = parseTimeToSeconds(entry.value);

      double startX = (startSeconds / totalDuration) * size.width;
      double endX = (endSeconds / totalDuration) * size.width;

      final regionPaint = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(startX, markerTop, endX - startX, markerHeight),
        regionPaint,
      );

      final borderPaint = Paint()
        ..color = Colors.red.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(
        Rect.fromLTWH(startX, markerTop, endX - startX, markerHeight),
        borderPaint,
      );

      final startMarkerPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      final startPath = Path();
      startPath.moveTo(startX, markerTop);
      startPath.lineTo(startX + 6, markerTop + markerHeight / 2);
      startPath.lineTo(startX, markerTop + markerHeight);
      startPath.close();
      canvas.drawPath(startPath, startMarkerPaint);

      canvas.drawLine(
        Offset(startX, markerTop),
        Offset(startX, markerTop + markerHeight),
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2.0,
      );

      final endMarkerPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.fill;

      final endPath = Path();
      endPath.moveTo(endX, markerTop);
      endPath.lineTo(endX - 6, markerTop + markerHeight / 2);
      endPath.lineTo(endX, markerTop + markerHeight);
      endPath.close();
      canvas.drawPath(endPath, endMarkerPaint);

      canvas.drawLine(
        Offset(endX, markerTop),
        Offset(endX, markerTop + markerHeight),
        Paint()
          ..color = Colors.orange
          ..strokeWidth = 2.0,
      );

      if (currentTime >= startSeconds - 5 && currentTime <= endSeconds + 5) {
        final glowPaint = Paint()
          ..color = Colors.red.withOpacity(0.2)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

        canvas.drawRect(
          Rect.fromLTWH(
            startX - 4,
            markerTop - 2,
            (endX - startX) + 8,
            markerHeight + 4,
          ),
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(EnhancedSkipMarkerPainter oldDelegate) {
    return oldDelegate.skipTimestamps != skipTimestamps ||
        oldDelegate.totalDuration != totalDuration ||
        oldDelegate.currentTime != currentTime;
  }
}

String pyPath(String path) {
  return "r'''${path.replaceAll("'''", "")}'''";
}
