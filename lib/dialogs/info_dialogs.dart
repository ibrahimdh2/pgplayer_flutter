// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../utils/file_extractor.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoDialogs {
  static void showSkipsDialog(
    BuildContext context,
    Map<String, String> skipTimestamps,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Active Skip Timestamps'),
        content: SizedBox(
          width: 300,
          child: skipTimestamps.isEmpty
              ? const Text('No skip timestamps configured')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: skipTimestamps.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 16),
                            const SizedBox(width: 8),
                            Text(entry.value),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void showKeyboardShortcuts(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⌨️ Keyboard Shortcuts'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShortcutRow('Space', 'Play/Pause'),
              _buildShortcutRow('← Left Arrow', 'Rewind 10 seconds'),
              _buildShortcutRow('→ Right Arrow', 'Forward 10 seconds'),
              _buildShortcutRow('S', 'Toggle Subtitles'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '💡 Tip: Right-click anywhere on the video for the full menu',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _buildShortcutRow(String key, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: Text(
              key,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(action, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  static void showExportJsonDialog(
    BuildContext context,
    String jsonString,
    Future<void> Function() onSaveToFile,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Timestamps JSON'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonString,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonString));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              await onSaveToFile();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Save to File'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void showLoadSkipsDialog(
    BuildContext context,
    String currentJson,
    Future<void> Function() onLoadFromFile,
    Function(String) onApply,
  ) {
    final TextEditingController controller = TextEditingController(
      text: currentJson,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Skip Timestamps JSON'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Format: {"1:02": "1:45", "2:30": "3:00"}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter JSON here',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await onLoadFromFile();
                    },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Load from File'),
                  ),
                ],
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
              onApply(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  static void showIMDBParentalGuideDialog(
    BuildContext context,
    String? videoPath,
  ) async {
    if (videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a video first')),
      );
      return;
    }

    String movieName = FileExtractor.extractMovieName(videoPath);

    showDialog(
      context: context,
      builder: (context) {
        TextEditingController nameController = TextEditingController(
          text: movieName,
        );

        return AlertDialog(
          title: const Text('Search Movie Parents Guide'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Movie/Show Name:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter movie or show name',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'The name was automatically extracted from the filename. '
                    'You can edit it if needed before searching.',
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
              onPressed: () async {
                Navigator.pop(context);
                String searchQuery = nameController.text.trim();

                if (searchQuery.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a movie name')),
                  );
                  return;
                }

                String googleSearchUrl =
                    'https://www.google.com/search?q=${Uri.encodeComponent('$searchQuery Parents Guide')}';

                try {
                  final Uri url = Uri.parse(googleSearchUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error opening Google: $e')),
                    );
                  }
                }
              },
              child: const Text('Search Google'),
            ),
          ],
        );
      },
    );
  }
}
