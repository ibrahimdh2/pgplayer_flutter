import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../utils/time_formatter.dart';
import 'package:pgplayer_flutter/models/app_state.dart';

class SkipManager {
  Map<String, String> generateSkipTimestamps(
    List<Map<String, dynamic>> detectedScenes,
    double totalDuration,
  ) {
    if (detectedScenes.isEmpty) {
      return {};
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

      newSkips[TimeFormatter.formatTime(start)] = TimeFormatter.formatTime(
        end.clamp(0, totalDuration),
      );
    }

    return newSkips;
  }

  bool shouldSkip(double currentTime, Map<String, String> skipTimestamps) {
    for (var entry in skipTimestamps.entries) {
      String skipFrom = entry.key;
      String skipTo = entry.value;

      double skipFromSeconds = TimeFormatter.parseTimeToSeconds(skipFrom);
      double skipToSeconds = TimeFormatter.parseTimeToSeconds(skipTo);

      if ((currentTime - skipFromSeconds).abs() < 0.5 &&
          currentTime < skipToSeconds) {
        return true;
      }
    }
    return false;
  }

  Duration? getSkipTarget(
    double currentTime,
    Map<String, String> skipTimestamps,
  ) {
    for (var entry in skipTimestamps.entries) {
      String skipFrom = entry.key;
      String skipTo = entry.value;

      double skipFromSeconds = TimeFormatter.parseTimeToSeconds(skipFrom);
      double skipToSeconds = TimeFormatter.parseTimeToSeconds(skipTo);

      if ((currentTime - skipFromSeconds).abs() < 0.5 &&
          currentTime < skipToSeconds) {
        return Duration(milliseconds: (skipToSeconds * 1000).toInt());
      }
    }
    return null;
  }

  String exportToJson(Map<String, String> skipTimestamps) {
    return const JsonEncoder.withIndent('  ').convert(skipTimestamps);
  }

  Map<String, String> importFromJson(String jsonString) {
    Map<String, dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<String?> pickJsonFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select Skip Timestamps JSON',
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        return await File(path).readAsString();
      }
      return null;
    } catch (e) {
      print('Error picking JSON file: $e');
      rethrow;
    }
  }

  Future<void> saveJsonFile(String jsonContent) async {
    try {
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Skip Timestamps',
        fileName: 'skip_timestamps.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath != null) {
        await File(outputPath).writeAsString(jsonContent);
      }
    } catch (e) {
      print('Error saving JSON file: $e');
      rethrow;
    }
  }
}
