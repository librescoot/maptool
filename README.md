# MapTool
[![CC BY-NC-SA 4.0][cc-by-nc-sa-shield]][cc-by-nc-sa]

MapTool is a Flutter application for downloading and processing OpenStreetMap vector tiles from Geofabrik. This tool specializes in fetching Shortbread MBTiles and optimizing them by removing unnecessary layers for specific use cases.

## Features

- Browse Geofabrik's complete region hierarchy
- Automatic detection of available Shortbread MBTiles
- Download progress tracking with visual feedback
- Process MBTiles by removing selected vector tile layers
- Cross-platform support (iOS, Android, Desktop)
- Hierarchical navigation through regions and subregions
- Temporary file management and cleanup

## Dependencies

- `flutter` - Cross-platform UI framework
- `http` - HTTP requests for downloading files
- `html` - HTML parsing for Geofabrik pages
- `sqflite` - SQLite database for MBTiles manipulation
- `archive` - GZIP compression/decompression
- `protobuf` - Vector tile format parsing
- `file_picker` - Native file save dialogs
- `path_provider` - Platform-specific storage paths
- `fixnum` - Fixed-width integer operations

## System Architecture

The application is structured around three main components:

- **Region Navigation**: Browse and navigate through Geofabrik's region hierarchy
- **Download Service**: Manages file downloads with progress tracking
- **MBTiles Processor**: Removes unnecessary layers from vector tiles

### Key Components

- **GeofabrikService**: Scrapes and parses Geofabrik download pages
- **DownloadService**: Handles file downloads with progress callbacks
- **MBTilesService**: Processes vector tiles using protobuf definitions
- **Region Models**: Data structures for regions and vector tiles
- **UI Screens**: Home screen for regions, detail screen for downloads

### Removed Layers

The following layers are automatically removed during processing:
- addresses
- aerialways
- boundaries
- boundary_labels
- bridges
- buildings
- dam_lines
- ferries
- ocean
- pier_lines
- pier_polygons
- place_labels
- pois
- public_transport
- street_polygons
- street_labels_points
- streets_polygons_labels
- sites
- water_lines
- water_lines_labels
- water_polygons_labels

## Building and Running

### Prerequisites

- Flutter SDK 3.3 or higher
- Dart SDK
- Platform-specific development tools (Xcode for iOS, Android Studio for Android)

### Build

```bash
flutter pub get
flutter build [platform]
```

Where `[platform]` can be:
- `apk` or `appbundle` for Android
- `ios` for iOS
- `windows`, `macos`, or `linux` for desktop

### Run

```bash
flutter run
```

## Usage

1. Launch the application
2. Browse available regions from the main screen
3. Navigate through subregions by tapping on entries
4. When a region has Shortbread tiles available, a download button appears
5. Tap "Download & Process Shortbread Tiles" to begin
6. Monitor download progress
7. Choose a save location for the processed file
8. The app automatically removes unnecessary layers and saves the optimized MBTiles

## Data Processing

The application processes MBTiles files by:
1. Decompressing GZIP-encoded vector tiles
2. Parsing protobuf-encoded tile data
3. Filtering out specified layers
4. Re-encoding and compressing the modified tiles
5. Saving the optimized MBTiles database

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This work is licensed under a
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License][cc-by-nc-sa].

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

[cc-by-nc-sa]: http://creativecommons.org/licenses/by-nc-sa/4.0/
[cc-by-nc-sa-image]: https://licensebuttons.net/l/by-nc-sa/4.0/88x31.png
[cc-by-nc-sa-shield]: https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg

---
Made with ❤️ by the LibreScoot community
