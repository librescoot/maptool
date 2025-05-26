import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/vector_tile.dart'; // This now imports the generated protobuf file

class MBTilesService {
  // This list now defines layers that are NOT kept by default when global settings are first initialized.
  static const List<String> defaultLayersToNotKeep = [
    'addresses',
    'aerialways',
    'boundaries',
    'boundary_labels',
    'bridges',
    'buildings',
    'dam_lines',
    'ferries',
    'ocean',
    'pier_lines',
    'pier_polygons',
    'place_labels',
    'pois',
    'public_transport',
    'street_polygons',
    'street_labels_points',
    'streets_polygons_labels',
    'sites',
    'water_lines',
    'water_lines_labels',
    'water_polygons_labels',
  ];

  // Static global state for layer selection. True means keep, false means remove.
  static Map<String, bool>? _staticGlobalLayersToKeepSelection;

  // Public getter for the selection
  // Now accesses the static variable.
  Map<String, bool> get globalLayersToKeepSelection {
    if (_staticGlobalLayersToKeepSelection == null) {
      // This should ideally not happen if initializeGlobalLayerSelectionsIfNeeded is called correctly.
      print("Warning: globalLayersToKeepSelection accessed before static initialization. Initializing with empty map.");
      _staticGlobalLayersToKeepSelection = {};
    }
    return _staticGlobalLayersToKeepSelection!;
  }

  // Method to initialize or update a specific layer's selection
  // Now updates the static variable.
  void setGlobalLayerKeepSelection(String layerName, bool shouldKeep) {
    _staticGlobalLayersToKeepSelection ??= {};
    _staticGlobalLayersToKeepSelection![layerName] = shouldKeep;
  }

  // Initializes the global selection if it hasn't been done yet.
  // Takes all available layer names to set up the initial state.
  // Now checks and initializes the static variable.
  void initializeGlobalLayerSelectionsIfNeeded(Iterable<String> allAvailableLayerNames) {
    if (_staticGlobalLayersToKeepSelection == null) {
      _staticGlobalLayersToKeepSelection = {};
      for (final layerName in allAvailableLayerNames) {
        // If a layer is in defaultLayersToNotKeep, it should NOT be kept by default (false).
        // Otherwise, it SHOULD be kept by default (true).
        _staticGlobalLayersToKeepSelection![layerName] = !defaultLayersToNotKeep.contains(layerName);
      }
      print("Global layer selections initialized (static): $_staticGlobalLayersToKeepSelection");
    }
  }


  static const Set<String> streetsToKeep = {
    'track',
    'path',
    'service',
    'unclassified',
    'residential',
    'tertiary',
    'secondary',
    'primary',
    'trunk',
    'living_street',
    'pedestrian',
    'taxiway',
    'busway',

    // "footway",
    // "motorway",
    // "rail",
    // "subway",
    // "light_rail",
    // "tram",
    // "narrow_gauge",
    // "cycleway",
    // "steps",
  };

  /// Processes an MBTiles file by removing specified layers
  /// Returns the path to the processed file
  Future<String> processMBTiles(
    String inputFilePath,
    String outputFilePath, {
    List<String>? dynamicLayersToRemove, // Optional parameter for dynamic layers
    void Function(double progress)? onProgress, // Callback for progress updates
  }) async {
    final Set<String> encounteredLayerNames = {}; // To store unique layer names
    // Initialize SQLite
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Copy the file first to preserve the original
    final tempFilePath = inputFilePath + '.temp';
    final inputFile = File(inputFilePath);
    await inputFile.copy(tempFilePath);

    // Open the database
    Database? db;
    try {
      db = await openDatabase(tempFilePath);

      // Check if it's a valid MBTiles file
      final tables = await db.query('sqlite_master',
          columns: ['name'], where: "type = 'table' AND name = 'tiles'");

      if (tables.isEmpty) {
        throw Exception('Not a valid MBTiles file (missing tiles table)');
      }

      // Get the count of tiles
      final countResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM tiles');
      final tileCount = Sqflite.firstIntValue(countResult) ?? 0;

      print('Processing $tileCount tiles...');

      // Process tiles in batches to avoid memory issues
      const batchSize = 100;
      int processedCount = 0;
      int modifiedCount = 0;

      for (int i = 0; i < tileCount; i += batchSize) {
        final tiles = await db.query(
          'tiles',
          columns: ['zoom_level', 'tile_column', 'tile_row', 'tile_data'],
          limit: batchSize,
          offset: i,
        );

        final batch = db.batch();

        for (final tile in tiles) {
          processedCount++;

          final zoomLevel = tile['zoom_level'] as int;
          final tileColumn = tile['tile_column'] as int;
          final tileRow = tile['tile_row'] as int;
          final tileData = tile['tile_data'] as Uint8List;

          try {
            // Pass the dynamic list of layers to remove to _processTileData
            final processedData = await _processTileData(tileData, encounteredLayerNames, dynamicLayersToRemove);

            // Only update if the tile was modified
            if (processedData != null) {
              batch.update(
                'tiles',
                {'tile_data': processedData},
                where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
                whereArgs: [zoomLevel, tileColumn, tileRow],
              );
              modifiedCount++;
            }
          } catch (e) {
            print(
                'Error processing tile at z=$zoomLevel, x=$tileColumn, y=$tileRow: $e');
          }

          // Provide progress updates
          if (onProgress != null) {
            final progress = tileCount > 0 ? processedCount / tileCount : 0.0;
            onProgress(progress);
          } else if (processedCount % 100 == 0) { // Fallback to console logging if no callback
            print(
                'Processed $processedCount / $tileCount tiles, modified $modifiedCount tiles');
          }
        }

        await batch.commit();
      }

      if (onProgress != null) {
        onProgress(1.0); // Ensure completion is reported
      }
      print('Processed $processedCount tiles, modified $modifiedCount tiles');
      print('Encountered layer types: ${encounteredLayerNames.toList()..sort()}');

      // Run VACUUM to reclaim space from removed layers
      print('Running VACUUM to optimize database size...');
      await db.execute('VACUUM');
      print('VACUUM completed');

      // Close the database
      await db.close();
      db = null;

      // Copy the processed file to the output location
      await File(tempFilePath).copy(outputFilePath);

      // Delete the temporary file
      await File(tempFilePath).delete();

      return outputFilePath;
    } catch (e) {
      print('Error processing MBTiles: $e');
      // Clean up
      if (db != null) {
        await db.close();
      }

      try {
        if (await File(tempFilePath).exists()) {
          await File(tempFilePath).delete();
        }
      } catch (e) {
        print('Error deleting temporary file: $e');
      }

      rethrow;
    }
  }

  /// Process an individual tile by removing specified layers
  Future<Uint8List?> _processTileData(
    Uint8List tileData,
    Set<String> encounteredLayerNames, [
    List<String>? currentLayersToRemove,
  ]) async {
    if (tileData.isEmpty) {
      return null;
    }

    final effectiveLayersToRemove = currentLayersToRemove ?? defaultLayersToNotKeep;


    try {
      // Decompress the tile data
      List<int> decompressedData;
      try {
        decompressedData = GZipDecoder().decodeBytes(tileData);
      } catch (e) {
        print('Error decompressing tile data: $e');
        return null;
      }

      // Parse the tile using generated protobuf code
      Tile tile;
      try {
        tile = Tile.fromBuffer(decompressedData);
      } catch (e) {
        print('Error parsing tile protobuf: $e');
        return null;
      }

      // Filter out the layers we want to remove
      bool modified = false;
      final filteredLayers = <Tile_Layer>[];

      for (final layer in tile.layers) {
        encounteredLayerNames.add(layer.name); // Collect layer name

        if (!effectiveLayersToRemove.contains(layer.name)) {
          if (layer.name == 'streets') {
            // if this is a street layer, we want to filter out some of the streets
            // that are not relevant to us.
            final List<Tile_Feature> filteredFeatures = [];

            features:
            for (final feature in layer.features) {
              for (int i = 0; i < feature.tags.length; i += 2) {
                if (i + 1 < feature.tags.length) {
                  final keyIndex = feature.tags[i];
                  final valueIndex = feature.tags[i + 1];
                  if (keyIndex < layer.keys.length &&
                      valueIndex < layer.values.length) {
                    final key = layer.keys[keyIndex];
                    final value = layer.values[valueIndex];
                    if (key == 'kind' &&
                        !streetsToKeep.contains(value.stringValue)) {
                      continue features;
                    }
                  }
                }
              }

              filteredFeatures.add(feature);
            }

            layer.features.clear();
            layer.features.addAll(filteredFeatures);
          }

          filteredLayers.add(layer);
        } else {
          modified = true;
          print('Removing layer: ${layer.name}');
        }
      }

      // If no layers were removed, return null to skip updating
      if (!modified) {
        return null;
      }

      // Create new tile with filtered layers
      final newTile = Tile()
        ..layers.clear()
        ..layers.addAll(filteredLayers);

      // Serialize the tile back to protobuf format
      final serializedData = newTile.writeToBuffer();

      // Compress with gzip
      final compressedData = GZipEncoder().encode(serializedData);

      if (compressedData == null) {
        throw Exception('Failed to compress tile data');
      }

      return Uint8List.fromList(compressedData);
    } catch (e) {
      print('Error processing vector tile: $e');
      return null;
    }
  }
}
