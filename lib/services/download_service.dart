import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

typedef ProgressCallback = void Function(double progress);

class DownloadService {
  /// Downloads a file from [url] and saves it to [targetFilePath].
  /// Returns the path to the downloaded file ([targetFilePath]).
  Future<String> downloadFile(
    String url,
    String targetFilePath, // Changed from filename to full path
    {ProgressCallback? onProgress}
  ) async {
    try {
      final file = File(targetFilePath);

      // Ensure the directory for the target file exists
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      
      print('Downloading $url to: $targetFilePath');
      
      // Proceed with download
      if (onProgress != null) {
        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();
        
        if (response.statusCode != 200) {
          // Attempt to delete partially downloaded file on error
          if (await file.exists()) {
            try { await file.delete(); } catch (_) {}
          }
          throw Exception('Failed to download file: HTTP ${response.statusCode} ${response.reasonPhrase}');
        }
        
        final totalBytes = response.contentLength;
        var receivedBytes = 0;
        
        final fileStream = file.openWrite();
        
        await for (final chunk in response) {
          receivedBytes += chunk.length;
          fileStream.add(chunk);
          
          if (totalBytes > 0 && totalBytes != -1) { // content-length can be -1
            onProgress(receivedBytes / totalBytes);
          } else {
            // If no content length, report indeterminate progress or based on chunks
            // For simplicity, can report 0 until done, or small increments
            onProgress(0.0); // Or some other heuristic
          }
        }
        
        await fileStream.close();
        httpClient.close();
        // Ensure 100% progress is reported at the end if onProgress was provided
        onProgress(1.0); 
      } else {
        // Simple download (no progress)
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
           if (await file.exists()) {
            try { await file.delete(); } catch (_) {}
          }
          throw Exception('Failed to download file: HTTP ${response.statusCode}');
        }
        await file.writeAsBytes(response.bodyBytes);
      }
      
      return targetFilePath;
    } catch (e) {
      // Attempt to delete partially downloaded file on any exception
      final file = File(targetFilePath);
      if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
      }
      throw Exception('Error downloading file $url: $e');
    }
  }

  // The getDownloadsDirectory and cleanupDownloads might be less relevant now
  // if we are not using a dedicated 'downloads' subfolder for these operations.
  // Keeping them for now in case they are used elsewhere or for other types of downloads.

  Future<Directory> getDownloadsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    // This now points to a generic 'downloads' folder, not necessarily where regions are stored.
    final downloadsDir = Directory('${directory.path}/downloads_temp'); 
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir;
  }
  
  Future<void> cleanupDownloads() async { // Renamed to avoid confusion
    try {
      final tempDownloadsDir = await getDownloadsDirectory();
      if (await tempDownloadsDir.exists()) {
        await tempDownloadsDir.delete(recursive: true);
        print("Cleaned up temp downloads directory: ${tempDownloadsDir.path}");
      }
    } catch (e) {
      print('Error cleaning up temp downloads: $e');
    }
  }

  // Copy a file to a new location
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
}
