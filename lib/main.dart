import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';

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

  // Skip timestamps: Map of "start_time" -> "skip_to_time"
  Map<String, String> skipTimestamps = {"0:05": "0:15", "0:30": "0:45"};

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
              content: Text('Skipped from $skipFrom to $skipTo'),
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
        ],
      ),
      backgroundColor: Colors.black,
      body: _buildNormalPlayer(),
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
