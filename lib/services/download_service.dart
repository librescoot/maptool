import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

typedef ProgressCallback = void Function(double progress);

class DownloadService {
  /// Downloads a file from [url] and saves it to the downloads directory
  /// Returns the path to the downloaded file
  Future<String> downloadFile(
    String url, 
    String filename, 
    {ProgressCallback? onProgress}
  ) async {
    try {
      // Get the downloads directory
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/downloads');
      
      // Create the downloads directory if it doesn't exist
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      
      final filePath = '${downloadsDir.path}/$filename';
      final file = File(filePath);

      // Check if the file already exists
      if (await file.exists()) {
        print('File already exists, using existing: $filePath');
        if (onProgress != null) {
          onProgress(1.0); // Report 100% progress immediately
        }
        return filePath; // Return the path to the existing file
      }
      
      // If file doesn't exist, proceed with download
      print('File not found locally, downloading: $filename');
      if (onProgress != null) {
        // For larger files with progress tracking, use HttpClient
        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();
        
        if (response.statusCode != 200) {
          throw Exception('Failed to download file: ${response.statusCode}');
        }
        
        // Get the total size
        final totalBytes = response.contentLength;
        var receivedBytes = 0;
        
        // Create the file
        final fileStream = file.openWrite();
        
        // Download the file with progress tracking
        await for (final chunk in response) {
          receivedBytes += chunk.length;
          fileStream.add(chunk);
          
          if (totalBytes > 0) {
            onProgress(receivedBytes / totalBytes);
          }
        }
        
        // Close the file
        await fileStream.close();
        httpClient.close();
      } else {
        // Simple download for smaller files or when progress isn't needed
        final response = await http.get(Uri.parse(url));
        
        if (response.statusCode != 200) {
          throw Exception('Failed to download file: ${response.statusCode}');
        }
        
        // Write the file
        await file.writeAsBytes(response.bodyBytes);
      }
      
      return filePath;
    } catch (e) {
      throw Exception('Error downloading file: $e');
    }
  }

  /// Get the directory where temporary downloads are stored
  Future<Directory> getDownloadsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${directory.path}/downloads');
    
    // Create the downloads directory if it doesn't exist
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    
    return downloadsDir;
  }
  
  /// Copy a file to a new location
  Future<String> copyFile(String sourcePath, String destinationPath) async {
    try {
      final sourceFile = File(sourcePath);
      
      if (!await sourceFile.exists()) {
        throw Exception('Source file does not exist: $sourcePath');
      }
      
      final destinationFile = await sourceFile.copy(destinationPath);
      return destinationFile.path;
    } catch (e) {
      throw Exception('Error copying file: $e');
    }
  }
  
  /// Delete a file
  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting file: $e');
    }
  }
  
  /// Clean up all temporary downloads
  Future<void> cleanupDownloads() async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      
      if (await downloadsDir.exists()) {
        final entities = await downloadsDir.list().toList();
        
        for (final entity in entities) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (e) {
              print('Error deleting file ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning up downloads: $e');
    }
  }
}
