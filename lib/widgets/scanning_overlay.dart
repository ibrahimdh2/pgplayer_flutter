import 'package:flutter/material.dart';
import '../utils/time_formatter.dart';
import 'package:pgplayer_flutter/models/app_state.dart';

class ScanningOverlay extends StatelessWidget {
  final double scanProgress;
  final int currentFrameNumber;
  final int totalFramesToScan;
  final int detectedScenesCount;
  final int parallelThreads;
  final DateTime? scanStartTime;

  const ScanningOverlay({
    super.key,
    required this.scanProgress,
    required this.currentFrameNumber,
    required this.totalFramesToScan,
    required this.detectedScenesCount,
    required this.parallelThreads,
    this.scanStartTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    'Frame: $currentFrameNumber / $totalFramesToScan',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Using Python multiprocessing with $parallelThreads workers',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
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
              'Estimated time: ${TimeFormatter.calculateEstimatedTime(scanStartTime, currentFrameNumber, totalFramesToScan)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
