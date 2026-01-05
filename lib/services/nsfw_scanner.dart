
/ ============================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class NSFWScanner {
  Future<ScanResult> scanVideo({
    required String videoPath,
    required double totalDuration,
    required String selectedDetector,
    required double sensitivityThreshold,
    required int parallelThreads,
    required Function(int, int, double) onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory('${tempDir.path}/frames');
    
    if (await framesDir.exists()) {
      await framesDir.delete(recursive: true);
    }
    await framesDir.create();

    int intervalSeconds = 2;
    int totalFrames = (totalDuration / intervalSeconds).ceil();

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final ffmpegPath = path.join(
      executableDir,
      "data/flutter_assets/assets/",
      'ffmpeg',
      'bin',
      'ffmpeg.exe',
    );

    // Extract frames
    List<Map<String, dynamic>> frameTasks = [];
    for (int i = 0; i < totalFrames; i++) {
      double timestamp = i * intervalSeconds.toDouble();
      String framePath =
          '${framesDir.path}/frame_${i}_${timestamp.toStringAsFixed(0)}.jpg';
      frameTasks.add({
        'index': i,
        'timestamp': timestamp,
        'path': framePath,
      });

      await Process.run(ffmpegPath, [
        '-ss',
        timestamp.toString(),
        '-i',
        videoPath,
        '-vframes',
        '1',
        '-q:v',
        '2',
        framePath,
      ]);

      onProgress(i + 1, totalFrames, (i + 1) / (totalFrames * 2));
    }

    // Analyze frames with Python
    List<Map<String, dynamic>> results = await _analyzeBatchWithPython(
      frameTasks: frameTasks,
      framesDir: framesDir.path,
      selectedDetector: selectedDetector,
      sensitivityThreshold: sensitivityThreshold,
      parallelThreads: parallelThreads,
      onProgress: (processed) {
        onProgress(processed, totalFrames, 0.5 + (processed / totalFrames * 0.5));
      },
    );

    // Collect NSFW scenes
    List<Map<String, dynamic>> detectedScenes = [];
    for (var result in results) {
      if (result['isNSFW'] == true) {
        detectedScenes.add({
          'timestamp': result['timestamp'],
          'frame': result['index'],
          'path': result['path'],
        });
      }
    }

    return ScanResult(
      detectedScenes: detectedScenes,
      totalFramesScanned: totalFrames,
    );
  }

  Future<List<Map<String, dynamic>>> _analyzeBatchWithPython({
    required List<Map<String, dynamic>> frameTasks,
    required String framesDir,
    required String selectedDetector,
    required double sensitivityThreshold,
    required int parallelThreads,
    required Function(int) onProgress,
  }) async {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final pythonExePath = path.join(
      executableDir,
      "data/flutter_assets/assets/",
      'detector.exe',
    );

    final inputJsonPath = '$framesDir/input.json';
    final resultPath = '$framesDir/results.json';
    final progressPath = '$framesDir/progress.txt';

    double actualThreshold = 1.0 - sensitivityThreshold;

    Map<String, dynamic> inputData = {
      'frames': frameTasks,
      'detector': selectedDetector,
      'threshold': actualThreshold,
      'threads': parallelThreads,
      'result_path': resultPath,
      'progress_path': progressPath,
    };

    await File(inputJsonPath).writeAsString(jsonEncode(inputData));

    if (!await File(inputJsonPath).exists()) {
      throw Exception('Failed to create input JSON file');
    }

    // Start progress monitoring
    Timer? progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) async {
        try {
          final progressFile = File(progressPath);
          if (await progressFile.exists()) {
            String content = await progressFile.readAsString();
            int processed = int.tryParse(content.trim()) ?? 0;
            onProgress(processed);
          }
        } catch (e) {
          // Ignore errors
        }
      },
    );

    ProcessResult result = await Process.run(pythonExePath, [
      '--input',
      inputJsonPath,
      '--output',
      resultPath,
    ]);

    progressTimer.cancel();

    print('Exit code: ${result.exitCode}');
    print('STDOUT: ${result.stdout}');
    print('STDERR: ${result.stderr}');

    if (result.exitCode != 0) {
      throw Exception(
        'Detector failed with exit code ${result.exitCode}: ${result.stderr}',
      );
    }

    final resultsFile = File(resultPath);
    if (!await resultsFile.exists()) {
      throw Exception('Results file not found at: $resultPath');
    }

    String jsonContent = await resultsFile.readAsString();
    if (jsonContent.isEmpty) {
      throw Exception('Results file is empty');
    }

    List<dynamic> jsonResults = jsonDecode(jsonContent);
    return jsonResults.map((item) => Map<String, dynamic>.from(item)).toList();
  }
}

class ScanResult {
  final List<Map<String, dynamic>> detectedScenes;
  final int totalFramesScanned;

  ScanResult({
    required this.detectedScenes,
    required this.totalFramesScanned,
  });
}
