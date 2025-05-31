enum RegionStatus {
  notDownloaded,
  downloading,
  downloaded,
  processing,
  processed,
  error
}

class Region {
  final String name;
  final String url; // Direct download URL for the mbtiles file (from GeofabrikService)

  // Stateful properties, managed at runtime
  String? filePath; // Path to the downloaded .mbtiles file (e.g., /path/to/Berlin.mbtiles)
  String? processedFilePath; // Path to the processed .mbtiles file (e.g., /path/to/Berlin_processed.mbtiles)
  RegionStatus status;
  double progress; // 0.0 to 1.0
  double? sizeMB; // Size in MB, can be null if not known
  String? lastUsedProfileId; // ID of the last used processing profile
  String? errorMessage; // To store error messages

  Region({
    required this.name,
    required this.url,
    this.filePath,
    this.processedFilePath,
    this.status = RegionStatus.notDownloaded,
    this.progress = 0.0,
    this.sizeMB,
    this.lastUsedProfileId,
    this.errorMessage,
  });

  // Helper to create a copy with updated values (immutable pattern)
  Region copyWith({
    String? name,
    String? url,
    String? filePath,
    String? processedFilePath,
    RegionStatus? status,
    double? progress,
    double? sizeMB, // Kept for UI mock, but won't be populated from Geofabrik
    String? lastUsedProfileId, // Could be persisted separately if needed
    String? errorMessage,
    bool clearErrorMessage = false, 
    bool clearProcessedFilePath = false,
  }) {
    return Region(
      name: name ?? this.name,
      url: url ?? this.url,
      filePath: filePath ?? this.filePath,
      processedFilePath: clearProcessedFilePath ? null : processedFilePath ?? this.processedFilePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      sizeMB: sizeMB ?? this.sizeMB,
      lastUsedProfileId: lastUsedProfileId ?? this.lastUsedProfileId,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'Region(name: $name, url: $url, status: $status, progress: $progress, filePath: $filePath, processedFilePath: $processedFilePath, sizeMB: $sizeMB)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is Region &&
      other.name == name &&
      other.url == url; // Assuming name and URL define uniqueness for now
  }

  @override
  int get hashCode => name.hashCode ^ url.hashCode;
}
