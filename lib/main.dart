import 'package:flutter/material.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:test_uploader/gallery_screen.dart';

// Background task handler - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('WorkManager task started: $task');
    debugPrint('Input data: $inputData');

    try {
      // Get data from inputData
      final url = inputData!['url'] as String;
      final filename = inputData['filename'] as String;
      final withNotification = inputData['withNotification'] as bool;
      final taskKey = inputData['taskKey'] as String;

      // Get download path
      final directory = await getExternalStorageDirectory();
      final parts = directory!.path.split('/');
      final basePath = '/${parts[1]}/${parts[2]}/${parts[3]}';
      final downloadFolder = Directory('$basePath/Download/test_download');
      if (!await downloadFolder.exists()) {
        await downloadFolder.create(recursive: true);
      }

      // Update state to downloading
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(taskKey, 'downloading');

      // // Configure FileDownloader for this isolate
      // FileDownloader().configureNotification(
      //   running: const TaskNotification(
      //     'Downloading {filename}',
      //     'Progress: {progress}',
      //   ),
      //   complete: const TaskNotification(
      //     'Download Complete',
      //     '{filename} has been downloaded',
      //   ),
      //   error: const TaskNotification(
      //     'Download Failed',
      //     '{filename} failed to download',
      //   ),
      //   progressBar: true,
      // );

      // Create download task
      final downloadTask = DownloadTask(
        url: url,
        filename: filename,
        directory: downloadFolder.path,
        baseDirectory: BaseDirectory.root,
        requiresWiFi: false,
        retries: 3,
        allowPause: true,
        displayName: withNotification ? filename : 'null',
      );

      // Execute download
      final result = await FileDownloader().download(
        downloadTask,
        onProgress: (progress) {
          debugPrint(
            'Download progress: ${(progress * 100).toStringAsFixed(1)}%',
          );
        },
        onStatus: (status) {
          debugPrint('Download status: $status');
        },
      );

      // Save result to SharedPreferences
      if (result.status == TaskStatus.complete) {
        await prefs.setString(taskKey, 'completed');
        await prefs.setString(
          '${taskKey}_path',
          '${downloadFolder.path}/$filename',
        );
        await prefs.setString(
          '${taskKey}_date',
          DateTime.now().toIso8601String(),
        );
        debugPrint('Download completed successfully!');
      } else {
        await prefs.setString(taskKey, 'failed');
        debugPrint('Download failed: ${result.status}');
      }

      return Future.value(true);
    } catch (e) {
      debugPrint('Error in background task: $e');
      // Save error state
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(inputData!['taskKey'] as String, 'failed');
      } catch (_) {}
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WorkManager
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // Enable debug mode for logging
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Downloader Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DownloadScreen(),
    );
  }
}

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  double _progressWithNotif = 0.0;
  double _progressWithoutNotif = 0.0;
  String _statusWithNotif = 'idle';
  String _statusWithoutNotif = 'idle';
  String _filePathWithNotif = '';
  String _filePathWithoutNotif = '';
  String _completionDateWithNotif = '';
  String _completionDateWithoutNotif = '';

  final String downloadUrl =
      'https://raw.githubusercontent.com/TestFileHub/FileHub/main/pdf/pdf50mb.pdf';
  final String fileName = 'pdf50mb.pdf';

  static const String taskKeyWithNotif = 'download_with_notif_status';
  static const String taskKeyWithoutNotif = 'download_without_notif_status';

  @override
  void initState() {
    super.initState();
    _initializeDownloader();
  }

  Future<void> _initializeDownloader() async {
    // Request permissions first
    await _requestPermissions();

    // Load saved state from SharedPreferences
    await _loadState();

    // Configure notifications for FileDownloader (main isolate)
    FileDownloader().configureNotification(
      running: const TaskNotification(
        'Downloading {filename}',
        'Progress: {progress}',
      ),
      complete: const TaskNotification(
        'Download Complete',
        '{filename} has been downloaded',
      ),
      error: const TaskNotification(
        'Download Failed',
        '{filename} failed to download',
      ),
      progressBar: true,
    );
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // Load state for download with notification
      _statusWithNotif = prefs.getString(taskKeyWithNotif) ?? 'idle';
      _filePathWithNotif = prefs.getString('${taskKeyWithNotif}_path') ?? '';
      _completionDateWithNotif =
          prefs.getString('${taskKeyWithNotif}_date') ?? '';

      // Load state for download without notification
      _statusWithoutNotif = prefs.getString(taskKeyWithoutNotif) ?? 'idle';
      _filePathWithoutNotif =
          prefs.getString('${taskKeyWithoutNotif}_path') ?? '';
      _completionDateWithoutNotif =
          prefs.getString('${taskKeyWithoutNotif}_date') ?? '';
    });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request storage permission for Android < 13
      await Permission.storage.request();

      // Request notification permission for Android 13+
      await Permission.notification.request();
    }
  }

  Future<String> _getDownloadPath() async {
    String basePath;

    if (Platform.isAndroid) {
      // For Android 9 and below, use external storage directory
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        // Extract the base path (usually /storage/emulated/0)
        final parts = directory.path.split('/');
        basePath = '/${parts[1]}/${parts[2]}/${parts[3]}';
      } else {
        // Fallback
        basePath = '/storage/emulated/0';
      }
    } else {
      final directory = await getApplicationDocumentsDirectory();
      basePath = directory.path;
    }

    // Create the 'Download/test_download' folder structure
    final downloadFolder = Directory('$basePath/Download/test_download');
    if (!await downloadFolder.exists()) {
      await downloadFolder.create(recursive: true);
    }

    return downloadFolder.path;
  }

  Future<void> _scheduleDownloadWithNotification() async {
    final prefs = await SharedPreferences.getInstance();

    // Update state to scheduled
    await prefs.setString(taskKeyWithNotif, 'scheduled');
    setState(() {
      _statusWithNotif = 'scheduled';
    });

    // Schedule WorkManager task with 1 minute delay
    await Workmanager().registerOneOffTask(
      'download-with-notif-task',
      'downloadWithNotification',
      initialDelay: const Duration(minutes: 1),
      inputData: {
        'url': downloadUrl,
        'filename': fileName,
        'withNotification': true,
        'taskKey': taskKeyWithNotif,
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download scheduled! Will start in 1 minute'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _scheduleDownloadWithoutNotification() async {
    final prefs = await SharedPreferences.getInstance();

    // Update state to scheduled
    await prefs.setString(taskKeyWithoutNotif, 'scheduled');
    setState(() {
      _statusWithoutNotif = 'scheduled';
    });

    // Schedule WorkManager task with 1 minute delay
    await Workmanager().registerOneOffTask(
      'download-without-notif-task',
      'downloadWithoutNotification',
      initialDelay: const Duration(minutes: 1),
      inputData: {
        'url': downloadUrl,
        'filename': fileName.replaceAll('.pdf', '_no_notif.pdf'),
        'withNotification': false,
        'taskKey': taskKeyWithoutNotif,
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download scheduled! Will start in 1 minute'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _resetState(String taskKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(taskKey);
    await prefs.remove('${taskKey}_path');
    await prefs.remove('${taskKey}_date');

    await _loadState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('State reset successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'idle':
        return 'Ready';
      case 'scheduled':
        return 'Scheduled (starts in 1 min)';
      case 'downloading':
        return 'Downloading...';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'downloading':
        return Colors.blue;
      case 'scheduled':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDownloadCard({
    required String title,
    required String status,
    required String filePath,
    required String completionDate,
    required VoidCallback onDownload,
    required VoidCallback onReset,
    required String taskKey,
    required IconData icon,
  }) {
    final isCompleted = status == 'completed';
    final isScheduledOrDownloading =
        status == 'scheduled' || status == 'downloading';
    final canDownload = !isCompleted && !isScheduledOrDownloading;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: canDownload ? onDownload : null,
              icon: Icon(icon),
              label: Text(
                canDownload
                    ? 'Schedule Download'
                    : isCompleted
                    ? 'Already Downloaded'
                    : 'Scheduled',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: canDownload ? null : Colors.grey[300],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Status: '),
                Text(
                  _getStatusText(status),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(status),
                  ),
                ),
              ],
            ),
            if (isCompleted) ...[
              const SizedBox(height: 8),
              Text(
                'File: $filePath',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
              if (completionDate.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Completed: ${_formatDate(completionDate)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
            if (!canDownload) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _resetState(taskKey),
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Background Downloader + WorkManager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const GalleryScreen()));
            },
            tooltip: 'Open Gallery',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadState,
            tooltip: 'Refresh State',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'How it works',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• Click "Schedule Download" to queue task'),
                    const Text('• WorkManager will start download in 1 minute'),
                    const Text(
                      '• Watch for debug notification from WorkManager',
                    ),
                    const Text('• State persists across app restarts'),
                    const Text('• Click "Reset" to clear and download again'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Download with Notification
            _buildDownloadCard(
              title: 'Download with Notification',
              status: _statusWithNotif,
              filePath: _filePathWithNotif,
              completionDate: _completionDateWithNotif,
              onDownload: _scheduleDownloadWithNotification,
              onReset: () => _resetState(taskKeyWithNotif),
              taskKey: taskKeyWithNotif,
              icon: Icons.download,
            ),
            const SizedBox(height: 16),

            // Download without Notification
            _buildDownloadCard(
              title: 'Download without Notification',
              status: _statusWithoutNotif,
              filePath: _filePathWithoutNotif,
              completionDate: _completionDateWithoutNotif,
              onDownload: _scheduleDownloadWithoutNotification,
              onReset: () => _resetState(taskKeyWithoutNotif),
              taskKey: taskKeyWithoutNotif,
              icon: Icons.download_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

// Gallery logic moved to gallery_screen.dart
