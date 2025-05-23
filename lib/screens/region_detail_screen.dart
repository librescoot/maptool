import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/region.dart';
import '../services/geofabrik_service.dart';
import '../services/download_service.dart';
import '../services/mbtiles_service.dart';

class RegionDetailScreen extends StatefulWidget {
  final Region region;

  const RegionDetailScreen({super.key, required this.region});

  @override
  _RegionDetailScreenState createState() => _RegionDetailScreenState();
}

class _RegionDetailScreenState extends State<RegionDetailScreen> {
  final GeofabrikService _geofabrikService = GeofabrikService();
  final DownloadService _downloadService = DownloadService();
  final MBTilesService _mbtilesService = MBTilesService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Region> _subRegions = [];
  bool _isDownloading = false;
  bool _isProcessing = false;
  double _downloadProgress = 0.0;
  String? _downloadPath;
  late Region _currentRegion;
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _currentRegion = widget.region;
    _loadRegionDetailsAndSubRegions();
  }

  Future<void> _loadRegionDetailsAndSubRegions() async {
    setState(() {
      _isLoading = true;
      _isLoadingDetails = true;
      _errorMessage = null;
    });

    try {
      // First, get the region details to retrieve shortbread URL
      final regionDetails = await _geofabrikService.fetchRegionDetails(widget.region);
      
      setState(() {
        _currentRegion = regionDetails;
        _isLoadingDetails = false;
      });
      
      // Then load subregions
      print('Fetching subregions for: ${_currentRegion.name} from URL: ${_currentRegion.url}');
      final subRegions = await _geofabrikService.fetchSubRegions(_currentRegion.url);
      print('Fetched ${subRegions.length} subregions for ${_currentRegion.name}');
      
      setState(() {
        _subRegions = subRegions;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading region details or subregions: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _isLoadingDetails = false;
      });
    }
  }

  Future<void> _downloadAndProcessShortbreadTiles() async {
    if (_currentRegion.shortbreadUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Shortbread tiles available for this region')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadPath = null;
    });

    try {
      // Extract filename from URL
      final url = _currentRegion.shortbreadUrl!;
      final filename = url.split('/').last;
      
      print('Downloading Shortbread tiles from: $url');
      
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
        _downloadPath = filePath;
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
      print('Error downloading Shortbread tiles: $e');
      
      setState(() {
        _isDownloading = false;
        _isProcessing = false;
        _errorMessage = e.toString();
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
      
      // Process the file by removing specified layers
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
        _errorMessage = e.toString();
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
    // If we're loading, show nothing yet
    if (_isLoading) return const SizedBox.shrink();
    
    // If we have an error, don't show the download bar
    if (_errorMessage != null) return const SizedBox.shrink();
    
    // Only show if we have a shortbread URL
    if (_currentRegion.shortbreadUrl == null) return const SizedBox.shrink();
    
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
                      Text('Processing MBTiles... Please wait.'),
                    ],
                  )
                : ElevatedButton.icon(
                    onPressed: _downloadAndProcessShortbreadTiles,
                    icon: const Icon(Icons.download),
                    label: const Text('Download & Process Shortbread Tiles'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_isLoadingDetails ? 'Checking for Shortbread tiles...' : 'Loading subregions...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error: $_errorMessage',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Region URL: ${_currentRegion.url}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadRegionDetailsAndSubRegions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_subRegions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No subregions found'),
            const SizedBox(height: 10),
            Text('Region: ${_currentRegion.name}', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text('URL: ${_currentRegion.url}', textAlign: TextAlign.center),
            if (_currentRegion.shortbreadUrl != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Shortbread Tiles Available!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentRegion.shortbreadUrl!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _subRegions.length,
      itemBuilder: (context, index) {
        final region = _subRegions[index];
        return ListTile(
          title: Text(region.name),
          subtitle: const Text(
            'Shortbread status will be checked when selected',
            style: TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegionDetailScreen(region: region),
              ),
            );
          },
        );
      },
    );
  }
} 