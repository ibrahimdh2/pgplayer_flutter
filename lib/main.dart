import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
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
  bool isFullscreen = false;
  bool showControls = true;
  Timer? hideControlsTimer;
  Timer? skipCheckTimer;
  String? videoPath;
  bool isInitialized = false;
  bool isScanning = false;
  double scanProgress = 0.0;

  // Skip timestamps: Map of "start_time" -> "skip_to_time"
  Map<String, String> skipTimestamps = {};

  // Detected NSFW scenes
  List<Map<String, dynamic>> detectedScenes = [];

  @override
  void initState() {
    super.initState();
    player = Player(configuration: PlayerConfiguration(title: 'PGPlayer'));
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );

    // Listen to player state changes
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

  @override
  void dispose() {
    hideControlsTimer?.cancel();
    skipCheckTimer?.cancel();
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
    });

    try {
      // Extract frames from video at intervals (every 2 seconds)
      final tempDir = await getTemporaryDirectory();
      final framesDir = Directory('${tempDir.path}/frames');
      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create();

      // Calculate total frames to extract
      int intervalSeconds = 2;
      int totalFrames = (totalDuration / intervalSeconds).ceil();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanning video... This may take a while')),
      );

      // Extract frames using ffmpeg command line
      for (int i = 0; i < totalFrames; i++) {
        double timestamp = i * intervalSeconds.toDouble();
        String framePath =
            '${framesDir.path}/frame_${i}_${timestamp.toStringAsFixed(0)}.jpg';

        // Use Process.run instead of FFmpegKit
        var result = await Process.run('ffmpeg', [
          '-ss',
          timestamp.toString(),
          '-i',
          videoPath!,
          '-vframes',
          '1',
          '-q:v',
          '2',
          framePath,
        ]);

        if (result.exitCode == 0) {
          // Analyze frame for NSFW content
          bool isNSFW = await analyzeFrameForNSFW(framePath);

          if (isNSFW) {
            // Mark this scene as NSFW
            detectedScenes.add({
              'timestamp': timestamp,
              'frame': i,
              'path': framePath,
            });
          }
        }

        setState(() {
          scanProgress = (i + 1) / totalFrames;
        });
      }

      // Generate skip timestamps from detected scenes
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

  Future<bool> analyzeFrameForNSFW(String framePath) async {
    try {
      // Read the image file
      final imageFile = File(framePath);
      if (!await imageFile.exists()) return false;

      // Get the current working directory to find the .venv
      final currentDir = Directory.current.path;
      final pythonPath = '$currentDir/.venv/bin/python3';

      // Check if python exists in venv
      if (!await File(pythonPath).exists()) {
        print('Python not found in .venv, using system python');
        // Fall back to system python
        var result = await Process.run('python3', [
          '-c',
          '''
import sys
sys.path.insert(0, "$currentDir/.venv/lib/python3.10/site-packages")
from nudenet import NudeDetector
detector = NudeDetector()
result = detector.detect("$framePath")
# Check for NSFW labels
nsfw_labels = ["FEMALE_GENITALIA_EXPOSED", "FEMALE_BREAST_EXPOSED", "MALE_GENITALIA_EXPOSED", 
               "ANUS_EXPOSED", "BUTTOCKS_EXPOSED"]
is_nsfw = any(item["class"] in nsfw_labels and item["score"] > 0.6 for item in result)
print("NSFW" if is_nsfw else "SAFE")
''',
        ]);

        if (result.exitCode == 0) {
          String output = result.stdout.toString().trim();
          return output.contains("NSFW");
        } else {
          print('Error running NudeNet: ${result.stderr}');
          return false;
        }
      }

      // Use the venv python
      var result = await Process.run(pythonPath, [
        '-c',
        '''
from nudenet import NudeDetector
detector = NudeDetector()
result = detector.detect("$framePath")
# Check for NSFW labels with high confidence
nsfw_labels = ["FEMALE_GENITALIA_EXPOSED", "FEMALE_BREAST_EXPOSED", "MALE_GENITALIA_EXPOSED", 
               "ANUS_EXPOSED", "BUTTOCKS_EXPOSED"]
is_nsfw = any(item["class"] in nsfw_labels and item["score"] > 0.6 for item in result)
print("NSFW" if is_nsfw else "SAFE")
''',
      ]);

      if (result.exitCode == 0) {
        String output = result.stdout.toString().trim();
        print('NudeNet result for frame: $output');
        return output.contains("NSFW");
      } else {
        print('Error running NudeNet: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('Error analyzing frame: $e');
      return false;
    }
  }

  void generateSkipTimestamps() {
    if (detectedScenes.isEmpty) {
      setState(() {
        skipTimestamps = {};
      });
      return;
    }

    // Group consecutive NSFW frames into scenes
    List<List<double>> sceneRanges = [];
    List<double> currentScene = [];

    for (var scene in detectedScenes) {
      double timestamp = scene['timestamp'];

      if (currentScene.isEmpty) {
        currentScene.add(timestamp);
      } else {
        // If frames are within 5 seconds, consider them same scene
        if (timestamp - currentScene.last <= 5) {
          currentScene.add(timestamp);
        } else {
          // Start new scene
          sceneRanges.add([...currentScene]);
          currentScene = [timestamp];
        }
      }
    }

    if (currentScene.isNotEmpty) {
      sceneRanges.add(currentScene);
    }

    // Convert scene ranges to skip timestamps
    Map<String, String> newSkips = {};
    for (var range in sceneRanges) {
      double start = range.first;
      double end = range.last + 5; // Add buffer after scene

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

      // Check if current time matches skip point (within 0.5 second tolerance)
      if ((currentTime - skipFromSeconds).abs() < 0.5 &&
          currentTime < skipToSeconds) {
        player.seek(Duration(milliseconds: (skipToSeconds * 1000).toInt()));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Skipped NSFW scene from $skipFrom to $skipTo'),
              duration: const Duration(seconds: 2),
            ),
          );
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

  void toggleFullscreen() {
    setState(() {
      isFullscreen = !isFullscreen;
    });
  }

  void resetControlsTimer() {
    hideControlsTimer?.cancel();
    setState(() {
      showControls = true;
    });
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
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'open_video',
          child: const Row(
            children: [
              Icon(Icons.folder_open, size: 20),
              SizedBox(width: 8),
              Text('Open Video File'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              pickAndLoadVideo();
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'scan_nsfw',
          child: const Row(
            children: [
              Icon(Icons.search, size: 20),
              SizedBox(width: 8),
              Text('Scan for NSFW Scenes'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              scanVideoForNSFW();
            });
          },
        ),
        PopupMenuItem<String>(
          value: 'export_json',
          child: const Row(
            children: [
              Icon(Icons.download, size: 20),
              SizedBox(width: 8),
              Text('Export Skip JSON'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              exportSkipJSON();
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'load_skips',
          child: const Row(
            children: [
              Icon(Icons.file_upload, size: 20),
              SizedBox(width: 8),
              Text('Load Skip JSON'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showLoadSkipsDialog(context);
            });
          },
        ),
        PopupMenuItem<String>(
          value: 'view_skips',
          child: const Row(
            children: [
              Icon(Icons.list, size: 20),
              SizedBox(width: 8),
              Text('View Skips'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showSkipsDialog(context);
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'speed',
          child: Row(
            children: [
              const Icon(Icons.speed, size: 20),
              const SizedBox(width: 8),
              Text('Speed: ${playbackSpeed}x'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showSpeedDialog(context);
            });
          },
        ),
      ],
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
            child: const Text('Load'),
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
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: skipTimestamps.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
    if (isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildFullscreenPlayer(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("PGPlayer - Desktop Video Player"),
        backgroundColor: const Color.fromARGB(255, 82, 176, 132),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: pickAndLoadVideo,
            tooltip: 'Open Video',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: isInitialized ? scanVideoForNSFW : null,
            tooltip: 'Scan for NSFW',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildNormalPlayer(),
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
                    const SizedBox(height: 20),
                    Text(
                      'Scanning video for NSFW content...',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 300,
                      child: LinearProgressIndicator(
                        value: scanProgress,
                        backgroundColor: Colors.grey[700],
                        color: const Color.fromARGB(255, 82, 176, 132),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(scanProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
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

  Widget _buildNormalPlayer() {
    return Column(
      children: [
        Expanded(
          child: MouseRegion(
            onHover: (_) => resetControlsTimer(),
            child: GestureDetector(
              onTap: togglePlayPause,
              onSecondaryTapDown: (details) {
                showContextMenu(context, details.globalPosition);
              },
              child: Stack(
                children: [
                  // Video area
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
                              ],
                            ),
                    ),
                  ),
                  // Skip indicator
                  if (skipTimestamps.isNotEmpty && isInitialized)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.skip_next,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${skipTimestamps.length} skips active',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Controls overlay
                  if ((showControls || !isPlaying) && isInitialized)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildControls(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenPlayer() {
    return MouseRegion(
      onHover: (_) => resetControlsTimer(),
      child: GestureDetector(
        onTap: togglePlayPause,
        onSecondaryTapDown: (details) {
          showContextMenu(context, details.globalPosition);
        },
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
                    : const Icon(Icons.movie, size: 200, color: Colors.white24),
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
          // Progress bar
          Row(
            children: [
              Text(
                formatTime(currentTime),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Expanded(
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
              Text(
                formatTime(totalDuration),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Control buttons
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
                      icon: const Icon(Icons.skip_next),
                      color: Colors.white,
                      tooltip: 'View skips',
                    ),
                  IconButton(
                    onPressed: toggleFullscreen,
                    icon: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                    color: Colors.white,
                    iconSize: 28,
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
