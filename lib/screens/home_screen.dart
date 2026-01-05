import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Import all our organized modules
import '../models/app_state.dart';
import '../services/video_service.dart';
import '../services/subtitle_service.dart';
import '../services/skip_manager.dart';
import '../services/nsfw_scanner.dart';
import '../widgets/scanning_overlay.dart';
import '../widgets/control_bar.dart';
import '../dialogs/settings_dialogs.dart';
import '../dialogs/info_dialogs.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Core components
  late final Player player;
  late VideoController controller;
  late final VideoService videoService;
  late final SubtitleService subtitleService;
  late final SkipManager skipManager;
  late final NSFWScanner nsfwScanner;
  final FocusNode _focusNode = FocusNode();

  // State
  late AppState state;

  // Timers
  Timer? hideControlsTimer;
  Timer? skipCheckTimer;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();

    // Initialize state
    state = AppState();

    // Initialize player and services
    player = Player(configuration: PlayerConfiguration(title: 'PGPlayer'));
    videoService = VideoService(player);
    subtitleService = SubtitleService(player);
    skipManager = SkipManager();
    nsfwScanner = NSFWScanner();

    _initializeController();
    _setupPlayerListeners();
    _startSkipCheckTimer();

    // Request focus for keyboard shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _initializeController() {
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: state.hardwareAcceleration,
      ),
    );
  }

  void _setupPlayerListeners() {
    player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          state = state.copyWith(isPlaying: playing);
        });
      }
    });

    player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          state = state.copyWith(currentTime: position.inMilliseconds / 1000.0);
        });
        _checkAndApplySkips();
      }
    });

    player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          state = state.copyWith(
            totalDuration: duration.inMilliseconds / 1000.0,
          );
        });
      }
    });
  }

  void _startSkipCheckTimer() {
    skipCheckTimer?.cancel();
    skipCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (state.isPlaying && state.isInitialized) {
        _checkAndApplySkips();
      }
    });
  }

  void _checkAndApplySkips() {
    if (!state.isInitialized) return;

    final skipTarget = skipManager.getSkipTarget(
      state.currentTime,
      state.skipTimestamps,
    );

    if (skipTarget != null) {
      if (state.autoSkipEnabled) {
        player.seek(skipTarget);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏭️ Skipped NSFW scene'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ NSFW content detected'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'Skip',
                textColor: Colors.white,
                onPressed: () => player.seek(skipTarget),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    hideControlsTimer?.cancel();
    skipCheckTimer?.cancel();
    _focusNode.dispose();
    player.dispose();
    super.dispose();
  }

  // Keyboard handler
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _togglePlayPause();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _stepBackward();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _stepForward();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        _toggleSubtitles();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // Video actions
  Future<void> _pickAndLoadVideo() async {
    try {
      final path = await videoService.pickVideoFile();
      if (path != null) {
        await videoService.loadVideo(path);
        setState(() {
          state = state.copyWith(videoPath: path, isInitialized: true);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video loaded successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading video: $e')));
      }
    }
  }

  // Subtitle actions
  Future<void> _pickAndLoadSubtitle() async {
    try {
      final path = await subtitleService.pickSubtitleFile();
      if (path != null) {
        await subtitleService.loadSubtitle(path);
        setState(() {
          state = state.copyWith(subtitlePath: path, showSubtitles: true);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subtitle loaded successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading subtitle: $e')));
      }
    }
  }

  void _toggleSubtitles() async {
    final newShowSubtitles = !state.showSubtitles;
    await subtitleService.toggleSubtitles(newShowSubtitles, state.subtitlePath);
    setState(() {
      state = state.copyWith(showSubtitles: newShowSubtitles);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newShowSubtitles ? 'Subtitles enabled' : 'Subtitles disabled',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _removeSubtitles() async {
    await subtitleService.removeSubtitles();
    setState(() {
      state = state.copyWith(subtitlePath: null, showSubtitles: false);
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subtitles removed')));
    }
  }

  // NSFW Scanning
  Future<void> _scanVideoForNSFW() async {
    if (state.videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a video first')),
      );
      return;
    }

    setState(() {
      state = state.copyWith(
        isScanning: true,
        scanProgress: 0.0,
        detectedScenes: [],
        currentFrameNumber: 0,
        detectedScenesCount: 0,
        scanStartTime: DateTime.now(),
      );
    });

    try {
      final result = await nsfwScanner.scanVideo(
        videoPath: state.videoPath!,
        totalDuration: state.totalDuration,
        selectedDetector: state.selectedDetector,
        sensitivityThreshold: state.sensitivityThreshold,
        parallelThreads: state.parallelThreads,
        onProgress: (currentFrame, totalFrames, progress) {
          if (mounted) {
            setState(() {
              state = state.copyWith(
                currentFrameNumber: currentFrame,
                totalFramesToScan: totalFrames,
                scanProgress: progress,
                detectedScenesCount: state.detectedScenes.length,
              );
            });
          }
        },
      );

      final skipTimestamps = skipManager.generateSkipTimestamps(
        result.detectedScenes,
        state.totalDuration,
      );

      setState(() {
        state = state.copyWith(
          detectedScenes: result.detectedScenes,
          skipTimestamps: skipTimestamps,
          detectedScenesCount: result.detectedScenes.length,
          isScanning: false,
          scanProgress: 1.0,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scan complete! Found ${result.detectedScenes.length} NSFW scenes',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        state = state.copyWith(isScanning: false);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error scanning video: $e')));
      }
    }
  }

  // Playback controls
  void _togglePlayPause() {
    if (!state.isInitialized) {
      _pickAndLoadVideo();
      return;
    }
    videoService.playOrPause();
  }

  void _stepBackward() {
    if (state.isInitialized) {
      videoService.stepBackward(state.currentTime, state.totalDuration);
    }
  }

  void _stepForward() {
    if (state.isInitialized) {
      videoService.stepForward(state.currentTime, state.totalDuration);
    }
  }

  void _onSeek(double value) {
    if (state.isInitialized) {
      videoService.seek(Duration(milliseconds: (value * 1000).toInt()));
    }
  }

  // Settings
  void _toggleGPUAcceleration() async {
    final newValue = !state.hardwareAcceleration;
    setState(() {
      state = state.copyWith(hardwareAcceleration: newValue);
    });

    if (state.isInitialized) {
      // Recreate controller with new settings
      bool wasPlaying = state.isPlaying;
      Duration currentPosition = player.state.position;
      String? currentPath = state.videoPath;

      setState(() {
        state = state.copyWith(isInitialized: false);
      });

      _initializeController();

      if (currentPath != null) {
        await player.open(Media(currentPath));
        if (state.subtitlePath != null) {
          await subtitleService.loadSubtitle(state.subtitlePath!);
        }
        await player.seek(currentPosition);
        if (wasPlaying) {
          await player.play();
        }
        setState(() {
          state = state.copyWith(isInitialized: true);
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPU Acceleration ${newValue ? 'enabled' : 'disabled'}',
          ),
        ),
      );
    }
  }

  // Skip management
  void _exportSkipJSON() {
    if (state.skipTimestamps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No skip timestamps to export')),
      );
      return;
    }

    final jsonString = skipManager.exportToJson(state.skipTimestamps);
    InfoDialogs.showExportJsonDialog(context, jsonString, () async {
      try {
        await skipManager.saveJsonFile(jsonString);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File saved successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
        }
      }
    });
  }

  void _loadSkipJSON() {
    final currentJson = jsonEncode(state.skipTimestamps);
    InfoDialogs.showLoadSkipsDialog(
      context,
      currentJson,
      () async {
        try {
          final content = await skipManager.pickJsonFile();
          if (content != null && mounted) {
            final timestamps = skipManager.importFromJson(content);
            setState(() {
              state = state.copyWith(skipTimestamps: timestamps);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Skip timestamps loaded!')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        }
      },
      (jsonText) {
        try {
          final timestamps = skipManager.importFromJson(jsonText);
          setState(() {
            state = state.copyWith(skipTimestamps: timestamps);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Skip timestamps loaded!')),
          );
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Invalid JSON: $e')));
        }
      },
    );
  }

  // Context menu
  void _showContextMenu(Offset position) {
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
      items: _buildMenuItems(),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      // FILE MENU
      _buildMenuHeader('📁 FILE'),
      _buildMenuItem(
        'open_video',
        Icons.folder_open,
        'Open Video',
        _pickAndLoadVideo,
      ),
      const PopupMenuDivider(),

      // SUBTITLES MENU
      _buildMenuHeader('💬 SUBTITLES'),
      _buildMenuItem(
        'add_subtitle',
        Icons.closed_caption,
        'Add Subtitle',
        _pickAndLoadSubtitle,
      ),
      if (state.subtitlePath != null)
        _buildMenuItem(
          'toggle_subtitle',
          state.showSubtitles ? Icons.subtitles : Icons.subtitles_off,
          state.showSubtitles ? 'Hide Subtitles (S)' : 'Show Subtitles (S)',
          _toggleSubtitles,
        ),
      if (state.subtitlePath != null)
        _buildMenuItem(
          'remove_subtitle',
          Icons.close,
          'Remove Subtitle',
          _removeSubtitles,
        ),
      const PopupMenuDivider(),

      // NSFW DETECTION
      _buildMenuHeader('🛡️ NSFW DETECTION'),
      _buildMenuItem(
        'scan_nsfw',
        Icons.search,
        'Scan for NSFW Scenes',
        _scanVideoForNSFW,
      ),
      _buildMenuItem(
        'skip_mode',
        state.autoSkipEnabled ? Icons.fast_forward : Icons.warning_amber,
        state.autoSkipEnabled ? 'Mode: Auto-Skip' : 'Mode: Warn Only',
        () => SettingsDialogs.showSkipModeDialog(
          context,
          state.autoSkipEnabled,
          (value) {
            setState(() {
              state = state.copyWith(autoSkipEnabled: value);
            });
          },
        ),
      ),
      _buildMenuItem(
        'detector_settings',
        Icons.settings,
        'Detection Settings',
        () => SettingsDialogs.showDetectorSettingsDialog(
          context,
          state.selectedDetector,
          state.sensitivityThreshold,
          (detector, threshold) {
            setState(() {
              state = state.copyWith(
                selectedDetector: detector,
                sensitivityThreshold: threshold,
              );
            });
          },
        ),
      ),
      const PopupMenuDivider(),

      // SKIP MANAGEMENT
      _buildMenuHeader('⏭️ SKIP MANAGEMENT'),
      _buildMenuItem(
        'view_skips',
        Icons.list,
        'View Skips',
        () => InfoDialogs.showSkipsDialog(context, state.skipTimestamps),
      ),
      _buildMenuItem(
        'load_skips',
        Icons.file_upload,
        'Load Skip JSON',
        _loadSkipJSON,
      ),
      _buildMenuItem(
        'export_json',
        Icons.download,
        'Export Skip JSON',
        _exportSkipJSON,
      ),
      const PopupMenuDivider(),

      // PLAYBACK
      _buildMenuHeader('⚙️ PLAYBACK'),
      _buildMenuItem(
        'speed',
        Icons.speed,
        'Speed: ${state.playbackSpeed}x',
        () => SettingsDialogs.showSpeedDialog(context, state.playbackSpeed, (
          speed,
        ) async {
          await videoService.setPlaybackRate(speed);
          setState(() {
            state = state.copyWith(playbackSpeed: speed);
          });
        }),
      ),
      _buildMenuItem(
        'gpu_acceleration',
        state.hardwareAcceleration
            ? Icons.check_box
            : Icons.check_box_outline_blank,
        'GPU Acceleration',
        _toggleGPUAcceleration,
      ),
      _buildMenuItem(
        'threads',
        Icons.memory,
        'Processing Threads: ${state.parallelThreads}',
        () => SettingsDialogs.showThreadsDialog(
          context,
          state.parallelThreads,
          (threads) {
            setState(() {
              state = state.copyWith(parallelThreads: threads);
            });
          },
        ),
      ),
      const PopupMenuDivider(),

      // INFO
      _buildMenuHeader('ℹ️ INFO'),
      _buildMenuItem(
        'imdb_guide',
        Icons.info_outline,
        'IMDB Parental Guide',
        () => InfoDialogs.showIMDBParentalGuideDialog(context, state.videoPath),
      ),
      _buildMenuItem(
        'keyboard_shortcuts',
        Icons.keyboard,
        'Keyboard Shortcuts',
        () => InfoDialogs.showKeyboardShortcuts(context),
      ),
    ];
  }

  PopupMenuItem<String> _buildMenuHeader(String text) {
    return PopupMenuItem<String>(
      enabled: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
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
      onTap: () => Future.delayed(Duration.zero, onTap),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Mouse handling for auto-hide controls
  void _onMouseMove() {
    if (!_isHovering) {
      _isHovering = true;
      _resetControlsTimer();
      Future.delayed(const Duration(milliseconds: 100), () {
        _isHovering = false;
      });
    }
  }

  void _resetControlsTimer() {
    hideControlsTimer?.cancel();
    if (!state.showControls) {
      setState(() {
        state = state.copyWith(showControls: true);
      });
    }
    if (state.isPlaying) {
      hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && state.isPlaying) {
          setState(() {
            state = state.copyWith(showControls: false);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildVideoPlayer(),
            if (state.isScanning)
              ScanningOverlay(
                scanProgress: state.scanProgress,
                currentFrameNumber: state.currentFrameNumber,
                totalFramesToScan: state.totalFramesToScan,
                detectedScenesCount: state.detectedScenesCount,
                parallelThreads: state.parallelThreads,
                scanStartTime: state.scanStartTime,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return GestureDetector(
      onTap: _togglePlayPause,
      onSecondaryTapDown: (details) {
        _showContextMenu(details.globalPosition);
      },
      child: MouseRegion(
        onHover: (_) => _onMouseMove(),
        child: Stack(
          children: [
            Container(
              color: Colors.black,
              child: Center(
                child: state.isInitialized
                    ? SizedBox.expand(
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                        ),
                      )
                    : _buildWelcomeScreen(),
              ),
            ),
            if (state.showControls && state.isInitialized) _buildTopControls(),
            if (state.skipTimestamps.isNotEmpty &&
                state.isInitialized &&
                state.showControls)
              _buildSkipIndicator(),
            if ((state.showControls || !state.isPlaying) && state.isInitialized)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ControlBar(
                  currentTime: state.currentTime,
                  totalDuration: state.totalDuration,
                  isPlaying: state.isPlaying,
                  playbackSpeed: state.playbackSpeed,
                  skipTimestamps: state.skipTimestamps,
                  subtitlePath: state.subtitlePath,
                  showSubtitles: state.showSubtitles,
                  onPlayPause: _togglePlayPause,
                  onStepBackward: _stepBackward,
                  onStepForward: _stepForward,
                  onToggleSubtitles: _toggleSubtitles,
                  onViewSkips: () => InfoDialogs.showSkipsDialog(
                    context,
                    state.skipTimestamps,
                  ),
                  onSeek: _onSeek,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie, size: 120, color: Colors.white24),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _pickAndLoadVideo,
          icon: const Icon(Icons.folder_open),
          label: const Text('Open Video File'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 82, 176, 132),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Right-click for menu • Space to play',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 10,
      right: 10,
      child: Row(
        children: [
          if (state.subtitlePath != null)
            GestureDetector(
              onTap: _toggleSubtitles,
              child: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  state.showSubtitles ? Icons.subtitles : Icons.subtitles_off,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          GestureDetector(
            onTap: () {
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              final size = renderBox.size;
              _showContextMenu(Offset(size.width - 50, 50));
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.more_vert, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipIndicator() {
    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Icon(
              state.autoSkipEnabled ? Icons.fast_forward : Icons.warning_amber,
              size: 16,
              color: state.autoSkipEnabled ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 6),
            Text(
              '${state.skipTimestamps.length} skip${state.skipTimestamps.length != 1 ? 's' : ''} (${state.autoSkipEnabled ? 'auto' : 'warn'})',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ALL DONE! Your modular PGPlayer is complete!
// ============================================================================
