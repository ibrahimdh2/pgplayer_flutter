import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';

class VideoService {
  final Player player;

  VideoService(this.player);

  Future<String?> pickVideoFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }
      return null;
    } catch (e) {
      print('Error picking video: $e');
      rethrow;
    }
  }

  Future<void> loadVideo(String path) async {
    await player.open(Media(path));
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  Future<void> playOrPause() async {
    await player.playOrPause();
  }

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> setPlaybackRate(double rate) async {
    await player.setRate(rate);
  }

  void stepBackward(double currentTime, double totalDuration) {
    final newPosition = Duration(
      milliseconds: ((currentTime - 10) * 1000)
          .clamp(0, totalDuration * 1000)
          .toInt(),
    );
    player.seek(newPosition);
  }

  void stepForward(double currentTime, double totalDuration) {
    final newPosition = Duration(
      milliseconds: ((currentTime + 10) * 1000)
          .clamp(0, totalDuration * 1000)
          .toInt(),
    );
    player.seek(newPosition);
  }
}
