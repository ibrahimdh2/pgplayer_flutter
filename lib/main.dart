import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: Home());
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final Player player;
  late final VideoController controller;

  bool isPlaying = false;
  double currentTime = 0.0;
  double totalDuration = 0.0;
  double playbackSpeed = 1.0;
  bool showControls = true;
  Timer? hideControlsTimer;
  Timer? skipCheckTimer;
  String? videoPath;
  bool isInitialized = false;
  bool isScanning = false;
  double scanProgress = 0.0;

  // Detection settings
  String selectedDetector = 'nudenet';
  double sensitivityThreshold = 0.6;

  // Auto-skip or warn setting
  bool autoSkipEnabled = true; // true = auto skip, false = just warn

  // Skip timestamps: Map of "start_time" -> "skip_to_time"
  Map<String, String> skipTimestamps = {};

  // Detected NSFW scenes
  List<Map<String, dynamic>> detectedScenes = [];

  @override
  void initState() {
    super.initState();
    player = Player(configuration: PlayerConfiguration(title: 'PGPlayer'));
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );

    player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          isPlaying = playing;
        });
      }
    });

    player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          currentTime = position.inMilliseconds / 1000.0;
        });
        checkAndApplySkips();
      }
    });

    player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          totalDuration = duration.inMilliseconds / 1000.0;
        });
      }
    });

    startSkipCheckTimer();
  }

  @override
  void dispose() {
    hideControlsTimer?.cancel();
    skipCheckTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> pickAndLoadVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        await loadVideo(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking video: $e')));
      }
    }
  }

  Future<void> loadVideo(String path) async {
    try {
      await player.open(Media(path));

      setState(() {
        videoPath = path;
        isInitialized = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video loaded successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading video: $e')));
      }
    }
  }

  Future<void> scanVideoForNSFW() async {
    if (videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a video first')),
      );
      return;
    }

    setState(() {
      isScanning = true;
      scanProgress = 0.0;
      detectedScenes = [];
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final framesDir = Directory('${tempDir.path}/frames');
      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create();

      int intervalSeconds = 2;
      int totalFrames = (totalDuration / intervalSeconds).ceil();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scanning video... This may take a while'),
        ),
      );

      for (int i = 0; i < totalFrames; i++) {
        double timestamp = i * intervalSeconds.toDouble();
        String framePath =
            '${framesDir.path}/frame_${i}_${timestamp.toStringAsFixed(0)}.jpg';

        var result = await Process.run('ffmpeg', [
          '-ss',
          timestamp.toString(),
          '-i',
          videoPath!,
          '-vframes',
          '1',
          '-q:v',
          '2',
          framePath,
        ]);

        if (result.exitCode == 0) {
          bool isNSFW = await analyzeFrameForNSFW(framePath);

          if (isNSFW) {
            detectedScenes.add({
              'timestamp': timestamp,
              'frame': i,
              'path': framePath,
            });
          }
        }

        setState(() {
          scanProgress = (i + 1) / totalFrames;
        });
      }

      generateSkipTimestamps();

      setState(() {
        isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scan complete! Found ${detectedScenes.length} NSFW scenes',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error scanning video: $e')));
      }
    }
  }

  Future<bool> analyzeFrameForNSFW(String framePath) async {
    try {
      final imageFile = File(framePath);
      if (!await imageFile.exists()) return false;

      final currentDir = Directory.current.path;
      final pythonPath = '$currentDir/.venv/bin/python3';

      String pythonScript = '';

      switch (selectedDetector) {
        case 'nudenet':
          pythonScript =
              '''
from nudenet import NudeDetector
detector = NudeDetector()
result = detector.detect("$framePath")
nsfw_labels = ["FEMALE_GENITALIA_EXPOSED", "FEMALE_BREAST_EXPOSED", "MALE_GENITALIA_EXPOSED", 
               "ANUS_EXPOSED", "BUTTOCKS_EXPOSED"]
is_nsfw = any(item["class"] in nsfw_labels and item["score"] > $sensitivityThreshold for item in result)
print("NSFW" if is_nsfw else "SAFE")
''';
          break;

        case 'nsfw_model':
          pythonScript =
              '''
from nsfw_detector import predict
import numpy as np
predictions = predict.classify("$framePath")
if "$framePath" in predictions:
    scores = predictions["$framePath"]
    nsfw_score = scores.get("porn", 0) + scores.get("hentai", 0)
    if $sensitivityThreshold < 0.7:
        nsfw_score += scores.get("sexy", 0) * 0.5
    is_nsfw = nsfw_score > $sensitivityThreshold
    print("NSFW" if is_nsfw else "SAFE")
else:
    print("SAFE")
''';
          break;

        case 'yahoo_open_nsfw':
          pythonScript =
              '''
import tensorflow as tf
import numpy as np
from PIL import Image

model = tf.keras.models.load_model("$currentDir/.venv/open_nsfw_model")

img = Image.open("$framePath").convert('RGB').resize((224, 224))
img_array = np.array(img) / 255.0
img_array = np.expand_dims(img_array, axis=0)

prediction = model.predict(img_array)
nsfw_score = prediction[0][1]

is_nsfw = nsfw_score > $sensitivityThreshold
print("NSFW" if is_nsfw else "SAFE")
''';
          break;

        case 'clip_interrogator':
          pythonScript =
              '''
import torch
from transformers import CLIPProcessor, CLIPModel
from PIL import Image

model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")

image = Image.open("$framePath")
inputs = processor(images=image, return_tensors="pt")

nsfw_prompts = [
    "explicit nudity", "naked person", "sexual content", 
    "pornographic image", "intimate body parts",
    "suggestive pose", "revealing clothing"
]
safe_prompts = ["normal clothed person", "safe content", "appropriate image"]

text_inputs = processor(text=nsfw_prompts + safe_prompts, return_tensors="pt", padding=True)

with torch.no_grad():
    image_features = model.get_image_features(**inputs)
    text_features = model.get_text_features(**text_inputs)
    
    image_features = image_features / image_features.norm(dim=-1, keepdim=True)
    text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    
    similarities = (image_features @ text_features.T).squeeze()

nsfw_sim = similarities[:len(nsfw_prompts)].max().item()
safe_sim = similarities[len(nsfw_prompts):].max().item()

is_nsfw = nsfw_sim > safe_sim and nsfw_sim > $sensitivityThreshold
print("NSFW" if is_nsfw else "SAFE")
''';
          break;
      }

      ProcessResult result;
      if (await File(pythonPath).exists()) {
        result = await Process.run(pythonPath, ['-c', pythonScript]);
      } else {
        result = await Process.run('python3', [
          '-c',
          'import sys; sys.path.insert(0, "$currentDir/.venv/lib/python3.10/site-packages"); ' +
              pythonScript,
        ]);
      }

      if (result.exitCode == 0) {
        String output = result.stdout.toString().trim();
        return output.contains("NSFW");
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  void generateSkipTimestamps() {
    if (detectedScenes.isEmpty) {
      setState(() {
        skipTimestamps = {};
      });
      return;
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

      newSkips[formatTime(start)] = formatTime(end.clamp(0, totalDuration));
    }

    setState(() {
      skipTimestamps = newSkips;
    });
  }

  void startSkipCheckTimer() {
    skipCheckTimer?.cancel();
    skipCheckTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (isPlaying && isInitialized) {
        checkAndApplySkips();
      }
    });
  }

  void checkAndApplySkips() {
    if (!isInitialized) return;

    for (var entry in skipTimestamps.entries) {
      String skipFrom = entry.key;
      String skipTo = entry.value;

      double skipFromSeconds = parseTimeToSeconds(skipFrom);
      double skipToSeconds = parseTimeToSeconds(skipTo);

      if ((currentTime - skipFromSeconds).abs() < 0.5 &&
          currentTime < skipToSeconds) {
        if (autoSkipEnabled) {
          // Auto-skip the scene
          player.seek(Duration(milliseconds: (skipToSeconds * 1000).toInt()));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⏭️ Skipped NSFW scene from $skipFrom to $skipTo',
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        } else {
          // Just warn the user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ NSFW content detected at $skipFrom'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.orange.shade700,
                action: SnackBarAction(
                  label: 'Skip',
                  textColor: Colors.white,
                  onPressed: () {
                    player.seek(
                      Duration(milliseconds: (skipToSeconds * 1000).toInt()),
                    );
                  },
                ),
              ),
            );
          }
        }
        break;
      }
    }
  }

  double parseTimeToSeconds(String time) {
    List<String> parts = time.split(':');
    if (parts.length == 2) {
      int minutes = int.tryParse(parts[0]) ?? 0;
      int seconds = int.tryParse(parts[1]) ?? 0;
      return minutes * 60.0 + seconds;
    }
    return 0.0;
  }

  String formatTime(double seconds) {
    int minutes = (seconds / 60).floor();
    int secs = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String extractMovieName(String filePath) {
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

  Future<void> openIMDBParentalGuide() async {
    if (videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please load a video first')),
      );
      return;
    }

    String movieName = extractMovieName(videoPath!);

    showDialog(
      context: context,
      builder: (context) {
        TextEditingController nameController = TextEditingController(
          text: movieName,
        );

        return AlertDialog(
          title: const Text('Open IMDB Parental Guide'),
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

                String encodedQuery = Uri.encodeComponent(searchQuery);
                String imdbSearchUrl =
                    'https://www.imdb.com/find/?q=$encodedQuery&s=tt&ttype=ft&ref_=fn_ft';

                try {
                  final Uri url = Uri.parse(imdbSearchUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Opening IMDB... Click on the movie and navigate to Parental Guide',
                          ),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  } else {
                    throw 'Could not launch URL';
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error opening IMDB: $e')),
                    );
                  }
                }
              },
              child: const Text('Open IMDB'),
            ),
          ],
        );
      },
    );
  }

  void stepBackward() {
    if (isInitialized) {
      final newPosition = Duration(
        milliseconds: ((currentTime - 10) * 1000)
            .clamp(0, totalDuration * 1000)
            .toInt(),
      );
      player.seek(newPosition);
    }
  }

  void stepForward() {
    if (isInitialized) {
      final newPosition = Duration(
        milliseconds: ((currentTime + 10) * 1000)
            .clamp(0, totalDuration * 1000)
            .toInt(),
      );
      player.seek(newPosition);
    }
  }

  void togglePlayPause() {
    if (!isInitialized) {
      pickAndLoadVideo();
      return;
    }
    player.playOrPause();
  }

  void resetControlsTimer() {
    hideControlsTimer?.cancel();
    setState(() {
      showControls = true;
    });
    if (isPlaying) {
      hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && isPlaying) {
          setState(() {
            showControls = false;
          });
        }
      });
    }
  }

  void exportSkipJSON() {
    if (skipTimestamps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No skip timestamps to export')),
      );
      return;
    }

    String jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(skipTimestamps);

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
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void showContextMenu(BuildContext context, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'open_video',
          child: const Row(
            children: [
              Icon(Icons.folder_open, size: 20),
              SizedBox(width: 8),
              Text('Open Video File'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              pickAndLoadVideo();
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'skip_mode',
          child: Row(
            children: [
              Icon(
                autoSkipEnabled ? Icons.fast_forward : Icons.warning_amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(autoSkipEnabled ? 'Mode: Auto-Skip' : 'Mode: Warn Only'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showSkipModeDialog(context);
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'detector_settings',
          child: const Row(
            children: [
              Icon(Icons.settings, size: 20),
              SizedBox(width: 8),
              Text('Detection Settings'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showDetectorSettingsDialog(context);
            });
          },
        ),
        PopupMenuItem<String>(
          value: 'scan_nsfw',
          child: const Row(
            children: [
              Icon(Icons.search, size: 20),
              SizedBox(width: 8),
              Text('Scan for NSFW Scenes'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              scanVideoForNSFW();
            });
          },
        ),
        PopupMenuItem<String>(
          value: 'export_json',
          child: const Row(
            children: [
              Icon(Icons.download, size: 20),
              SizedBox(width: 8),
              Text('Export Skip JSON'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              exportSkipJSON();
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'imdb_guide',
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 20),
              SizedBox(width: 8),
              Text('IMDB Parental Guide'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              openIMDBParentalGuide();
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'load_skips',
          child: const Row(
            children: [
              Icon(Icons.file_upload, size: 20),
              SizedBox(width: 8),
              Text('Load Skip JSON'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showLoadSkipsDialog(context);
            });
          },
        ),
        PopupMenuItem<String>(
          value: 'view_skips',
          child: const Row(
            children: [
              Icon(Icons.list, size: 20),
              SizedBox(width: 8),
              Text('View Skips'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showSkipsDialog(context);
            });
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'speed',
          child: Row(
            children: [
              const Icon(Icons.speed, size: 20),
              const SizedBox(width: 8),
              Text('Speed: ${playbackSpeed}x'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showSpeedDialog(context);
            });
          },
        ),
      ],
    );
  }

  void _showSkipModeDialog(BuildContext context) {
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
                setState(() {
                  autoSkipEnabled = value!;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value! ? '✅ Auto-skip enabled' : '⚠️ Warn mode enabled',
                    ),
                  ),
                );
              },
            ),
            RadioListTile<bool>(
              title: const Text('Warn Only'),
              subtitle: const Text('Show warning with manual skip option'),
              value: false,
              groupValue: autoSkipEnabled,
              onChanged: (value) {
                setState(() {
                  autoSkipEnabled = value!;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value! ? '✅ Auto-skip enabled' : '⚠️ Warn mode enabled',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetectorSettingsDialog(BuildContext context) {
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
                const Text(
                  'Detection Model:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  title: const Text('NudeNet'),
                  subtitle: const Text('Fast, detects explicit nudity'),
                  value: 'nudenet',
                  groupValue: tempDetector,
                  onChanged: (value) {
                    setDialogState(() {
                      tempDetector = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('NSFW Detector'),
                  subtitle: const Text('Balanced, detects porn/hentai/sexy'),
                  value: 'nsfw_model',
                  groupValue: tempDetector,
                  onChanged: (value) {
                    setDialogState(() {
                      tempDetector = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('CLIP Interrogator'),
                  subtitle: const Text(
                    'Most sensitive, catches subtle content',
                  ),
                  value: 'clip_interrogator',
                  groupValue: tempDetector,
                  onChanged: (value) {
                    setDialogState(() {
                      tempDetector = value!;
                    });
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Sensitivity Threshold:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Low'),
                    Expanded(
                      child: Slider(
                        value: tempSensitivity,
                        min: 0.3,
                        max: 0.9,
                        divisions: 12,
                        label: tempSensitivity.toStringAsFixed(2),
                        onChanged: (value) {
                          setDialogState(() {
                            tempSensitivity = value;
                          });
                        },
                      ),
                    ),
                    const Text('High'),
                  ],
                ),
                Text(
                  'Current: ${tempSensitivity.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Lower threshold = More sensitive (catches minor scenes)\n'
                    'Higher threshold = Less sensitive (only explicit scenes)',
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
                setState(() {
                  selectedDetector = tempDetector;
                  sensitivityThreshold = tempSensitivity;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Using ${tempDetector.toUpperCase()} with sensitivity ${tempSensitivity.toStringAsFixed(2)}',
                    ),
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoadSkipsDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: jsonEncode(skipTimestamps),
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
              try {
                Map<String, dynamic> decoded = jsonDecode(controller.text);
                setState(() {
                  skipTimestamps = decoded.map(
                    (key, value) => MapEntry(key, value.toString()),
                  );
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Skip timestamps loaded!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Invalid JSON: $e')));
              }
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  void _showSkipsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Active Skip Timestamps'),
        content: SizedBox(
          width: 300,
          child: skipTimestamps.isEmpty
              ? const Text('No skip timestamps configured')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: skipTimestamps.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
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
                setState(() {
                  playbackSpeed = value!;
                  player.setRate(playbackSpeed);
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildPlayer(),
          if (isScanning)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color.fromARGB(255, 82, 176, 132),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Scanning video for NSFW content...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 300,
                      child: LinearProgressIndicator(
                        value: scanProgress,
                        backgroundColor: Colors.grey[700],
                        color: const Color.fromARGB(255, 82, 176, 132),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(scanProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    return MouseRegion(
      onHover: (_) => resetControlsTimer(),
      child: GestureDetector(
        onTap: togglePlayPause,
        onSecondaryTapDown: (details) {
          showContextMenu(context, details.globalPosition);
        },
        child: Stack(
          children: [
            Container(
              color: Colors.black,
              child: Center(
                child: isInitialized
                    ? SizedBox.expand(
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.movie,
                            size: 120,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: pickAndLoadVideo,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Open Video File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(
                                255,
                                82,
                                176,
                                132,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Right-click for menu',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            // Menu button overlay (top-right)
            if (showControls && isInitialized)
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  onPressed: () {
                    final RenderBox renderBox =
                        context.findRenderObject() as RenderBox;
                    final size = renderBox.size;
                    showContextMenu(context, Offset(size.width - 50, 50));
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            // Skip indicator
            if (skipTimestamps.isNotEmpty && isInitialized && showControls)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        autoSkipEnabled
                            ? Icons.fast_forward
                            : Icons.warning_amber,
                        size: 16,
                        color: autoSkipEnabled ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${skipTimestamps.length} skip${skipTimestamps.length != 1 ? 's' : ''} (${autoSkipEnabled ? 'auto' : 'warn'})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Controls overlay
            if ((showControls || !isPlaying) && isInitialized)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildControls()),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
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
                formatTime(currentTime),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Expanded(
                child: Slider(
                  value: currentTime.clamp(0.0, totalDuration),
                  min: 0,
                  max: totalDuration > 0 ? totalDuration : 1,
                  activeColor: const Color.fromARGB(255, 82, 176, 132),
                  inactiveColor: Colors.grey[700],
                  onChanged: (value) {
                    if (isInitialized) {
                      player.seek(
                        Duration(milliseconds: (value * 1000).toInt()),
                      );
                    }
                  },
                ),
              ),
              Text(
                formatTime(totalDuration),
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
                    onPressed: stepBackward,
                    icon: const Icon(Icons.replay_10),
                    color: Colors.white,
                    iconSize: 28,
                  ),
                  IconButton(
                    onPressed: togglePlayPause,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    color: const Color.fromARGB(255, 82, 176, 132),
                    iconSize: 36,
                  ),
                  IconButton(
                    onPressed: stepForward,
                    icon: const Icon(Icons.forward_10),
                    color: Colors.white,
                    iconSize: 28,
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
                  if (skipTimestamps.isNotEmpty)
                    IconButton(
                      onPressed: () => _showSkipsDialog(context),
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
