// ============================================================================
import 'package:flutter/material.dart';

class SettingsDialogs {
  static void showSkipModeDialog(
    BuildContext context,
    bool autoSkipEnabled,
    Function(bool) onChanged,
  ) {
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
                onChanged(value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<bool>(
              title: const Text('Warn Only'),
              subtitle: const Text('Show warning with manual skip option'),
              value: false,
              groupValue: autoSkipEnabled,
              onChanged: (value) {
                onChanged(value!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  static void showDetectorSettingsDialog(
    BuildContext context,
    String selectedDetector,
    double sensitivityThreshold,
    Function(String, double) onApply,
  ) {
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
                    '✅ Higher value = More sensitive (catches more scenes)\n'
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
                onApply(tempDetector, tempSensitivity);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  static void showSpeedDialog(
    BuildContext context,
    double playbackSpeed,
    Function(double) onSpeedChanged,
  ) {
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
                onSpeedChanged(value!);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  static void showThreadsDialog(
    BuildContext context,
    int parallelThreads,
    Function(int) onThreadsChanged,
  ) {
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
                  onThreadsChanged(value!);
                  Navigator.pop(context);
                },
              );
            })),
          ],
        ),
      ),
    );
  }
}
