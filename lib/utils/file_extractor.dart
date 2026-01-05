import 'dart:io';
import 'package:flutter/services.dart';

class FileExtractor {
  static Future<void> extractFile({
    required String assetPath,
    required String targetPath,
  }) async {
    try {
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();
      await targetFile.writeAsBytes(bytes);
      print('Extracted: $assetPath -> $targetPath');
    } catch (e) {
      print('Failed to extract $assetPath: $e');
      rethrow;
    }
  }

  static String extractMovieName(String filePath) {
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
}
