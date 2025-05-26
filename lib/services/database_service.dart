import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/profile.dart';
import './mbtiles_service.dart'; // Import MBTilesService to access default layer lists

class DatabaseService {
  static const _databaseName = "MapTool.db";
  static const _databaseVersion = 1;

  static const tableProfiles = 'profiles';

  // Column names for profiles table
  static const columnProfileId = 'id'; 
  static const columnProfileName = 'name'; // TEXT
  static const columnProfileLayersToKeep = 'layersToKeep'; // TEXT (comma-separated)
  // static const columnProfileLayersToRemove = 'layersToRemove'; // TEXT (comma-separated) - REMOVED
  static const columnProfileIsDefault = 'isDefault'; // INTEGER (0 or 1)

  // Singleton instance
  DatabaseService._privateConstructor();
  static final DatabaseService instance = DatabaseService._privateConstructor();

  // Only have a single app-wide reference to the database
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(path,
        version: _databaseVersion,
        onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableProfiles (
        $columnProfileId TEXT PRIMARY KEY,
        $columnProfileName TEXT NOT NULL UNIQUE,
        $columnProfileLayersToKeep TEXT,
        $columnProfileIsDefault INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create a default profile
    // Layers to keep are those NOT in MBTilesService.defaultLayersToNotKeep
    final allKnownLayers = MBTilesService.publicLayerDescriptions.keys.toList();
    final defaultLayersToKeep = allKnownLayers
        .where((layer) => !MBTilesService.defaultLayersToNotKeep.contains(layer))
        .toList();

    final defaultProfile = Profile(
      id: 'default_profile_001',
      name: 'Default',
      isDefault: true,
      layersToKeep: defaultLayersToKeep,
    );
    await db.insert(tableProfiles, defaultProfile.toMap());
  }

  // Profile CRUD
  Future<int> insertProfile(Profile profile) async {
    Database db = await instance.database;
    return await db.insert(tableProfiles, profile.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Profile>> getAllProfiles() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(tableProfiles, orderBy: '$columnProfileName ASC');
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) {
      return Profile.fromMap(maps[i]);
    });
  }

  Future<Profile?> getProfile(String id) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableProfiles,
      where: '$columnProfileId = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Profile.fromMap(maps.first);
    }
    return null;
  }
  
  Future<Profile?> getDefaultProfile() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableProfiles,
      where: '$columnProfileIsDefault = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Profile.fromMap(maps.first);
    }
    // Fallback if no default is explicitly set (should not happen with _onCreate)
    final allProfiles = await getAllProfiles();
    return allProfiles.isNotEmpty ? allProfiles.first : null;
  }

  Future<int> updateProfile(Profile profile) async {
    Database db = await instance.database;
    return await db.update(
      tableProfiles,
      profile.toMap(),
      where: '$columnProfileId = ?',
      whereArgs: [profile.id],
    );
  }

  Future<int> deleteProfile(String id) async {
    Database db = await instance.database;
    return await db.delete(
      tableProfiles,
      where: '$columnProfileId = ?',
      whereArgs: [id],
    );
  }

  // Helper to ensure only one default profile
  Future<void> setDefaultProfile(String profileId) async {
    Database db = await instance.database;
    await db.transaction((txn) async {
      // Unset current default
      await txn.update(tableProfiles, {columnProfileIsDefault: 0}, where: '$columnProfileIsDefault = ?', whereArgs: [1]);
      // Set new default
      await txn.update(tableProfiles, {columnProfileIsDefault: 1}, where: '$columnProfileId = ?', whereArgs: [profileId]);
    });
  }

  // Helper to recreate the default profile with proper layer selections
  Future<void> ensureValidDefaultProfile() async {
    final defaultProfile = await getDefaultProfile();
    
    // Check if default profile exists and has layers
    if (defaultProfile == null || defaultProfile.layersToKeep.isEmpty) {
      print('Default profile missing or empty, recreating...');
      
      // Get all known layers and determine which should be kept by default
      final allKnownLayers = MBTilesService.publicLayerDescriptions.keys.toList();
      final defaultLayersToKeep = allKnownLayers
          .where((layer) => !MBTilesService.defaultLayersToNotKeep.contains(layer))
          .toList();
      
      print('Creating default profile with layers: $defaultLayersToKeep');
      
      Database db = await instance.database;
      
      if (defaultProfile != null) {
        // Update existing default profile
        final updatedProfile = Profile(
          id: defaultProfile.id,
          name: defaultProfile.name,
          isDefault: true,
          layersToKeep: defaultLayersToKeep,
        );
        await updateProfile(updatedProfile);
      } else {
        // Create new default profile
        final newDefaultProfile = Profile(
          id: 'default_profile_001',
          name: 'Default',
          isDefault: true,
          layersToKeep: defaultLayersToKeep,
        );
        await insertProfile(newDefaultProfile);
      }
    }
  }
}
