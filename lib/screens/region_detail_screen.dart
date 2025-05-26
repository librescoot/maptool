import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/region.dart';
import '../services/download_service.dart';
import '../services/mbtiles_service.dart';

class RegionDetailScreen extends StatefulWidget {
  final Region region;

  const RegionDetailScreen({super.key, required this.region});

  @override
  _RegionDetailScreenState createState() => _RegionDetailScreenState();
}

class _RegionDetailScreenState extends State<RegionDetailScreen> {
  final DownloadService _downloadService = DownloadService();
  final MBTilesService _mbtilesService = MBTilesService();
  bool _isDownloading = false;
  bool _isProcessing = false;
  double _downloadProgress = 0.0;
  late Region _currentRegion;

  @override
  void initState() {
    super.initState();
    _currentRegion = widget.region;
  }

  Future<void> _downloadAndProcessMBTilesFile() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      // Extract filename from URL
      final url = _currentRegion.url;
      final filename = url.split('/').last;
      
      print('Downloading MBTiles file from: $url');
      
      // Download the file with progress tracking
      final filePath = await _downloadService.downloadFile(
        url, 
        filename,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );
      
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _isProcessing = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download complete. Starting to process...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Now ask the user where to save the processed file
      await _processAndSaveTiles(filePath);
      
    } catch (e) {
      print('Error downloading MBTiles file: $e');
      
      setState(() {
        _isDownloading = false;
        _isProcessing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${e.toString()}')),
      );
    }
  }


  Future<void> _processAndSaveTiles(String downloadedFilePath) async {
    try {
      // Ask user for a location to save the file
      final saveLocation = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Processed MBTiles File',
        fileName: '${_currentRegion.name.replaceAll(' ', '_')}_processed.mbtiles',
        allowedExtensions: ['mbtiles'],
        type: FileType.custom,
      );
      
      if (saveLocation == null) {
        // User cancelled the save dialog
        setState(() {
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saving cancelled')),
        );
        
        // Clean up downloaded file
        await _downloadService.deleteFile(downloadedFilePath);
        return;
      }
      
      // Process the MBTiles file by removing specified layers
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing MBTiles file... This may take a while.'),
          duration: Duration(seconds: 5),
        ),
      );
      
      print('Processing MBTiles file: $downloadedFilePath');
      print('Saving to: $saveLocation');
      
      final processedFilePath = await _mbtilesService.processMBTiles(
        downloadedFilePath, 
        saveLocation,
      );
      
      print('Processed MBTiles saved to: $processedFilePath');
      
      setState(() {
        _isProcessing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Processed file saved to: $processedFilePath'),
          duration: const Duration(seconds: 5),
        ),
      );
      
      // Clean up downloaded file
      await _downloadService.deleteFile(downloadedFilePath);
      
    } catch (e) {
      print('Error processing or saving MBTiles: $e');
      
      setState(() {
        _isProcessing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing failed: ${e.toString()}')),
      );
      
      // Clean up downloaded file
      await _downloadService.deleteFile(downloadedFilePath);
    }
  }

  @override
  void dispose() {
    // Clean up any temporary files when leaving the screen
    _cleanupDownloads();
    super.dispose();
  }

  Future<void> _cleanupDownloads() async {
    try {
      await _downloadService.cleanupDownloads();
    } catch (e) {
      print('Error cleaning up downloads: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentRegion.name),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: _isDownloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _downloadProgress),
                  const SizedBox(height: 8),
                  Text('Downloading: ${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                ],
              )
            : _isProcessing
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Processing MBTiles file... Please wait.'),
                    ],
                  )
                : ElevatedButton.icon(
                    onPressed: _downloadAndProcessMBTilesFile,
                    icon: const Icon(Icons.download),
                    label: const Text('Download & Process MBTiles'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
      ),
    );
  }

  Widget _buildBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              _currentRegion.name.toUpperCase(),
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Shortbread MBTiles',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link, color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(width: 8),
                        const Text('Source:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentRegion.url,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Click the download button below to download and process the MBTiles data for this region.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
} 