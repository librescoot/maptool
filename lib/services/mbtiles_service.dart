import 'dart:io';
import 'dart:isolate'; // Required for Isolate.current.debugName

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart'; // Required for compute
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/vector_tile.dart';

// Helper class for passing arguments to the isolate for tile processing.
class _TileProcessingArgs {
  final Uint8List tileData;
  final List<String> effectiveLayersToRemove;

  _TileProcessingArgs(this.tileData, this.effectiveLayersToRemove);
}

// Helper class for returning results from isolate-based tile processing.
class _TileProcessingResult {
  final Uint8List? processedData;
  final bool modified;

  _TileProcessingResult(this.processedData, this.modified);
}

// This top-level function will run in an isolate
Future<_TileProcessingResult> _processTileDataIsolate(_TileProcessingArgs args) async {
  bool modified = false;

  if (args.tileData.isEmpty) {
    return _TileProcessingResult(null, modified);
  }

  try {
    List<int> decompressedData;
    try {
      decompressedData = const GZipDecoder().decodeBytes(args.tileData);
    } catch (e) {
      print('Isolate ${Isolate.current.debugName}: Error decompressing tile data: $e');
      return _TileProcessingResult(null, modified);
    }

    Tile tile;
    try {
      tile = Tile.fromBuffer(decompressedData);
    } catch (e) {
      print('Isolate ${Isolate.current.debugName}: Error parsing tile protobuf: $e');
      return _TileProcessingResult(null, modified);
    }

    final filteredLayers = <Tile_Layer>[];
    for (final layer in tile.layers) {
      if (!args.effectiveLayersToRemove.contains(layer.name)) {
        if (layer.name == 'streets') {
          final List<Tile_Feature> filteredFeatures = [];
          features:
          for (final feature in layer.features) {
            for (int i = 0; i < feature.tags.length; i += 2) {
              if (i + 1 < feature.tags.length) {
                final keyIndex = feature.tags[i];
                final valueIndex = feature.tags[i + 1];
                if (keyIndex < layer.keys.length && valueIndex < layer.values.length) {
                  final key = layer.keys[keyIndex];
                  final value = layer.values[valueIndex];
                  if (key == 'kind' && !MBTilesService.streetsToKeep.contains(value.stringValue)) {
                    continue features;
                  }
                }
              }
            }
            filteredFeatures.add(feature);
          }
          if (layer.features.length != filteredFeatures.length) {
            modified = true; // Features were removed from this layer
          }
          layer.features.clear();
          layer.features.addAll(filteredFeatures);
        }
        filteredLayers.add(layer);
      } else {
        modified = true;
        // print('Isolate ${Isolate.current.debugName}: Removing layer: ${layer.name}');
      }
    }

    if (!modified) {
      return _TileProcessingResult(null, false);
    }

    final newTile = Tile()
      ..layers.clear()
      ..layers.addAll(filteredLayers);

    final serializedData = newTile.writeToBuffer();
    final compressedData = const GZipEncoder().encode(serializedData);

    return _TileProcessingResult(Uint8List.fromList(compressedData), true);
  } catch (e) {
    print('Isolate ${Isolate.current.debugName}: Error processing vector tile: $e');
    return _TileProcessingResult(null, modified); // return what we have
  }
}

class MBTilesService {
  static const List<String> defaultLayersToNotKeep = [
    'addresses', 'aerialways', 'boundaries', 'boundary_labels', 'bridges',
    'buildings', 'dam_lines', 'ferries', 'ocean', 'pier_lines', 'pier_polygons',
    'place_labels', 'pois', 'public_transport', 'street_polygons',
    'street_labels_points', 'streets_polygons_labels', 'sites', 'water_lines',
    'water_lines_labels', 'water_polygons_labels',
  ];

  static final Map<String, String> layerDescriptions = {
    'addresses': 'Individual address points.',
    'aerialways': 'Cable cars, ski lifts, etc.',
    'boundaries': 'Administrative and other boundaries.',
    'boundary_labels': 'Labels for boundaries.',
    'bridges': 'Bridge structures.',
    'buildings': 'Building footprints.',
    'dam_lines': 'Lines representing dams.',
    'ferries': 'Ferry routes.',
    'land': 'General land use areas.',
    'ocean': 'Areas representing oceans.',
    'pier_lines': 'Lines representing piers.',
    'pier_polygons': 'Polygons representing piers.',
    'place_labels': 'Labels for cities, towns, and other places.',
    'pois': 'Points of Interest.',
    'public_transport': 'Public transport routes and stops.',
    'sites': 'Various site polygons (e.g., parks, industrial areas).',
    'streets': 'Street centerlines.',
    'street_labels': 'General labels for streets.',
    'street_labels_points': 'Point labels for streets.',
    'street_polygons': 'Polygons representing streets (e.g., pedestrian areas).',
    'streets_polygons_labels': 'Labels for street polygons.',
    'water_lines': 'Lines representing rivers, streams, etc.',
    'water_lines_labels': 'Labels for water lines (rivers, streams).',
    'water_polygons': 'Polygons representing lakes, reservoirs, etc.',
    'water_polygons_labels': 'Labels for water polygons (lakes, reservoirs).',
  };

  // Public getter for layer descriptions
  static Map<String, String> get publicLayerDescriptions => layerDescriptions;

  // Define all known layer names based on the layerDescriptions map
  static final List<String> _allKnownLayerNames = layerDescriptions.keys.toList();

  // This map stores the user's preference for keeping (true) or removing (false) each layer
  static final Map<String, bool> _staticGlobalLayersToKeepSelection =
      Map.fromEntries(
    _allKnownLayerNames.map(
      (layerName) => MapEntry(
        layerName,
        !defaultLayersToNotKeep.contains(layerName),
      ),
    ),
  );

  Map<String, bool> get globalLayersToKeepSelection {
    return _staticGlobalLayersToKeepSelection;
  }

  void setGlobalLayerKeepSelection(String layerName, bool shouldKeep) {
    if (_staticGlobalLayersToKeepSelection.containsKey(layerName)) {
      _staticGlobalLayersToKeepSelection[layerName] = shouldKeep;
    } else {
      print("Warning: Attempted to set selection for unknown layer: $layerName");
    }
  }

  static const Set<String> streetsToKeep = {
    'track', 'path', 'service', 'unclassified', 'residential', 'tertiary',
    'secondary', 'primary', 'trunk', 'living_street', 'pedestrian', 'taxiway', 'busway',
  };

  Future<String> processMBTiles(
    String inputFilePath,
    String outputFilePath, {
    List<String>? dynamicLayersToRemove,
    void Function(double progress)? onProgress,
  }) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final tempFilePath = '$inputFilePath.temp';
    final inputFile = File(inputFilePath);
    await inputFile.copy(tempFilePath);

    Database? db;
    try {
      db = await openDatabase(tempFilePath);
      final tables = await db.query('sqlite_master', columns: ['name'], where: "type = 'table' AND name = 'tiles'");
      if (tables.isEmpty) {
        throw Exception('Not a valid MBTiles file (missing tiles table)');
      }

      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM tiles');
      final tileCount = Sqflite.firstIntValue(countResult) ?? 0;
      print('Processing $tileCount tiles...');

      const batchSize = 100; // DB read batch size
      int processedTilesInLoop = 0;
      int totalModifiedTiles = 0;

      final effectiveLayersToRemove = dynamicLayersToRemove ??
          _staticGlobalLayersToKeepSelection.entries
              .where((entry) => !entry.value) // Find layers marked not to keep
              .map((entry) => entry.key)
              .toList();

      for (int i = 0; i < tileCount; i += batchSize) {
        final tilesData = await db.query(
          'tiles',
          columns: ['zoom_level', 'tile_column', 'tile_row', 'tile_data'],
          limit: batchSize,
          offset: i,
        );

        if (tilesData.isEmpty) break;

        List<Future<_TileProcessingResult>> processingFutures = [];
        for (final tileMap in tilesData) {
          final tileData = tileMap['tile_data'] as Uint8List;
          final args = _TileProcessingArgs(tileData, effectiveLayersToRemove);
          processingFutures.add(compute(_processTileDataIsolate, args));
        }

        final List<_TileProcessingResult> results = await Future.wait(processingFutures);
        
        final batch = db.batch();
        int currentBatchModifiedCount = 0;

        for (int j = 0; j < results.length; j++) {
          processedTilesInLoop++;
          final result = results[j];

          if (result.modified && result.processedData != null) {
            final originalTileInfo = tilesData[j];
            batch.update(
              'tiles',
              {'tile_data': result.processedData},
              where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
              whereArgs: [
                originalTileInfo['zoom_level'] as int,
                originalTileInfo['tile_column'] as int,
                originalTileInfo['tile_row'] as int
              ],
            );
            currentBatchModifiedCount++;
          }
        }

        if (currentBatchModifiedCount > 0) {
          await batch.commit(noResult: true);
          totalModifiedTiles += currentBatchModifiedCount;
        }


        if (onProgress != null) {
          final progress = tileCount > 0 ? processedTilesInLoop / tileCount : 0.0;
          onProgress(progress);
        } else if (processedTilesInLoop % (batchSize * 5) == 0 || processedTilesInLoop == tileCount) { // Log less frequently
          print('Processed $processedTilesInLoop / $tileCount tiles, total modified $totalModifiedTiles tiles');
        }
      }

      if (onProgress != null) {
        onProgress(1.0);
      }
      print('Finished processing. Processed $processedTilesInLoop tiles, total modified $totalModifiedTiles tiles.');

      print('Running VACUUM to optimize database size...');
      await db.execute('VACUUM');
      print('VACUUM completed');

      await db.close();
      db = null;

      await File(tempFilePath).copy(outputFilePath);
      await File(tempFilePath).delete();

      return outputFilePath;
    } catch (e) {
      print('Error processing MBTiles: $e');
      if (db != null && db.isOpen) {
        await db.close();
      }
      try {
        if (await File(tempFilePath).exists()) {
          await File(tempFilePath).delete();
        }
      } catch (deleteError) {
        print('Error deleting temporary file: $deleteError');
      }
      rethrow;
    }
  }
}
