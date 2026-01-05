import 'package:flutter/material.dart';
import '../utils/time_formatter.dart';
import 'skip_marker_painter.dart';

class ControlBar extends StatelessWidget {
  final double currentTime;
  final double totalDuration;
  final bool isPlaying;
  final double playbackSpeed;
  final Map<String, String> skipTimestamps;
  final String? subtitlePath;
  final bool showSubtitles;
  final VoidCallback onPlayPause;
  final VoidCallback onStepBackward;
  final VoidCallback onStepForward;
  final VoidCallback onToggleSubtitles;
  final VoidCallback onViewSkips;
  final Function(double) onSeek;

  const ControlBar({
    super.key,
    required this.currentTime,
    required this.totalDuration,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.skipTimestamps,
    this.subtitlePath,
    required this.showSubtitles,
    required this.onPlayPause,
    required this.onStepBackward,
    required this.onStepForward,
    required this.onToggleSubtitles,
    required this.onViewSkips,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
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
                TimeFormatter.formatTime(currentTime),
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
                            painter: SkipMarkerPainter(
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
                        onChanged: onSeek,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                TimeFormatter.formatTime(totalDuration),
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
                    onPressed: onStepBackward,
                    icon: const Icon(Icons.replay_10),
                    color: Colors.white,
                    iconSize: 28,
                    tooltip: 'Rewind 10s (←)',
                  ),
                  IconButton(
                    onPressed: onPlayPause,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    color: const Color.fromARGB(255, 82, 176, 132),
                    iconSize: 36,
                    tooltip: 'Play/Pause (Space)',
                  ),
                  IconButton(
                    onPressed: onStepForward,
                    icon: const Icon(Icons.forward_10),
                    color: Colors.white,
                    iconSize: 28,
                    tooltip: 'Forward 10s (→)',
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
                  if (subtitlePath != null)
                    IconButton(
                      onPressed: onToggleSubtitles,
                      icon: Icon(
                        showSubtitles ? Icons.subtitles : Icons.subtitles_off,
                      ),
                      color: Colors.white,
                      tooltip: 'Toggle Subtitles (S)',
                    ),
                  if (skipTimestamps.isNotEmpty)
                    IconButton(
                      onPressed: onViewSkips,
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
