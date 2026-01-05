import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';

class SubtitleService {
  final Player player;

  SubtitleService(this.player);

  Future<String?> pickSubtitleFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }
      return null;
    } catch (e) {
      print('Error picking subtitle: $e');
      rethrow;
    }
  }

  Future<void> loadSubtitle(String path) async {
    await player.setSubtitleTrack(SubtitleTrack.uri(path));
  }

  Future<void> toggleSubtitles(bool show, String? subtitlePath) async {
    if (show && subtitlePath != null) {
      await player.setSubtitleTrack(SubtitleTrack.uri(subtitlePath));
    } else {
      await player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  Future<void> removeSubtitles() async {
    await player.setSubtitleTrack(SubtitleTrack.no());
  }
}
