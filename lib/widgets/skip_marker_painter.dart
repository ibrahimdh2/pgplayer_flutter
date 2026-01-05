import 'package:flutter/material.dart';
import 'package:pgplayer_flutter/models/app_state.dart';
import '../utils/time_formatter.dart';

class SkipMarkerPainter extends CustomPainter {
  final Map<String, String> skipTimestamps;
  final double totalDuration;
  final double currentTime;

  SkipMarkerPainter({
    required this.skipTimestamps,
    required this.totalDuration,
    required this.currentTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final markerHeight = 12.0;
    final markerTop = (size.height - markerHeight) / 2;

    for (var entry in skipTimestamps.entries) {
      double startSeconds = TimeFormatter.parseTimeToSeconds(entry.key);
      double endSeconds = TimeFormatter.parseTimeToSeconds(entry.value);

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
  bool shouldRepaint(SkipMarkerPainter oldDelegate) {
    return oldDelegate.skipTimestamps != skipTimestamps ||
        oldDelegate.totalDuration != totalDuration ||
        oldDelegate.currentTime != currentTime;
  }
}
