import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

import '../models/region.dart';
import '../models/profile.dart';
import '../services/geofabrik_service.dart';
import '../services/database_service.dart';
import '../services/download_service.dart';
import '../services/mbtiles_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GeofabrikService _geofabrikService = GeofabrikService();
  final DatabaseService _dbService = DatabaseService.instance;
  final DownloadService _downloadService = DownloadService();
  final MBTilesService _mbtilesService = MBTilesService();

  bool _isLoadingRegions = true;
  bool _isLoadingProfiles = true;
  String? _errorMessage;
  List<Region> _regions = [];
  List<Profile> _profiles = [];
  Profile? _defaultProfile;

  final Map<String, RegionStatus> _activeOperations = {};
  final Map<String, double> _operationProgress = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<String> get _documentsPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  String _generateFileName(String regionName, {bool processed = false}) {
    final sanitizedName = regionName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    return processed ? '${sanitizedName}_processed.mbtiles' : '$sanitizedName.mbtiles';
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingRegions = true;
      _isLoadingProfiles = true;
      _errorMessage = null;
    });

    try {
      await _dbService.ensureValidDefaultProfile();
      
      final profiles = await _dbService.getAllProfiles();
      final defaultProfile = await _dbService.getDefaultProfile();
      final staticRegions = await _geofabrikService.fetchRegions();
      final documentsPath = await _documentsPath;
      
      List<Region> enrichedRegions = [];
      for (var staticRegion in staticRegions) {
        String originalFilePath = p.join(documentsPath, _generateFileName(staticRegion.name));
        String processedFilePath = p.join(documentsPath, _generateFileName(staticRegion.name, processed: true));
        File originalFile = File(originalFilePath);
        File processedFile = File(processedFilePath);
        bool originalExists = await originalFile.exists();
        bool processedExists = await processedFile.exists();
        RegionStatus status = RegionStatus.notDownloaded;

        if (processedExists) {
          status = RegionStatus.processed;
        } else if (originalExists) {
          status = RegionStatus.downloaded;
        }
        
        enrichedRegions.add(
          staticRegion.copyWith(
            filePath: originalExists ? originalFilePath : null,
            processedFilePath: processedExists ? processedFilePath : null,
            status: status,
            progress: (status == RegionStatus.downloaded || status == RegionStatus.processed) ? 1.0 : 0.0,
          )
        );
      }
      
      if (mounted) {
        setState(() {
          _regions = enrichedRegions;
          _profiles = profiles;
          _defaultProfile = defaultProfile;
          _isLoadingRegions = false;
          _isLoadingProfiles = false;
        });
      }
    } catch (e, s) {
      print('Error loading initial data: $e\n$s');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoadingRegions = false;
          _isLoadingProfiles = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LibreScoot MapTool'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => _showManageProfilesDialog(context),
            tooltip: 'Manage Profiles',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingRegions || _isLoadingProfiles ? null : _loadInitialData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoadingRegions || _isLoadingProfiles) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Loading map data...")
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $_errorMessage', style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _loadInitialData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_regions.isEmpty) {
      return const Center(child: Text('No regions found.'));
    }

    return ListView.builder(
      itemCount: _regions.length,
      itemBuilder: (context, index) {
        final region = _regions[index];
        return _buildRegionListItem(region);
      },
    );
  }

  Widget _buildRegionListItem(Region region) {
    final currentStatus = _activeOperations[region.name] ?? region.status;
    final currentProgress = _operationProgress[region.name] ?? region.progress;

    List<Widget> buttons = [];
    switch (currentStatus) {
      case RegionStatus.notDownloaded:
        buttons.add(_buildDownloadButton(region));
        break;
      case RegionStatus.error: 
        buttons.add(_buildDownloadButton(region));
        if (region.filePath != null || region.processedFilePath != null) {
          buttons.add(const SizedBox(width: 8));
          buttons.add(_buildCleanButton(region));
        }
        break;
      case RegionStatus.downloading:
        buttons.add(_buildInProgressButton(currentStatus, currentProgress, "Downloading"));
        break;
      case RegionStatus.processing:
        buttons.add(_buildRedownloadButton(region, disabled: true));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildCleanButton(region, disabled: true));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildInProgressButton(currentStatus, currentProgress, "Processing"));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessOptionsButton(region, disabled: true));
        break;
      case RegionStatus.downloaded:
        buttons.add(_buildRedownloadButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildCleanButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessOptionsButton(region));
        break;
      case RegionStatus.processed:
        buttons.add(_buildRedownloadButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildCleanButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessButton(region)); 
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessOptionsButton(region));
        break;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      region.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...buttons,
                ],
              ),
              if (region.errorMessage != null && currentStatus == RegionStatus.error)
                Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text('Error: ${region.errorMessage}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }

  Widget _buildDownloadButton(Region region) {
    return TextButton.icon(
      icon: const Icon(Icons.download, size: 18),
      label: const Text('Download'),
      onPressed: () => _onDownload(region),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        foregroundColor: Colors.green,
      ),
    );
  }

  Widget _buildInProgressButton(RegionStatus status, double progress, String operationName) {
    bool isDeterminate = progress > 0 && progress < 1;
    return TextButton.icon(
      icon: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: isDeterminate ? progress : null)),
      label: Text('$operationName ${isDeterminate ? '${(progress * 100).toStringAsFixed(0)}%' : ''}'),
      onPressed: null, 
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          disabledForegroundColor: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
          foregroundColor: status == RegionStatus.downloading ? Colors.green : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildRedownloadButton(Region region, {bool disabled = false}) {
    return TextButton.icon(
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Redownload'),
      onPressed: disabled ? null : () => _onRedownload(region),
      style: TextButton.styleFrom(
        foregroundColor: disabled ? Colors.grey.shade400 : Colors.orange,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Widget _buildCleanButton(Region region, {bool disabled = false}) {
    return TextButton.icon(
      icon: const Icon(Icons.delete_outline, size: 18),
      label: const Text('Clean'),
      onPressed: disabled ? null : () => _onDelete(region),
      style: TextButton.styleFrom(
        foregroundColor: disabled ? Colors.grey.shade400 : Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Widget _buildProcessButton(Region region, {bool disabled = false}) {
    return TextButton.icon(
      icon: const Icon(Icons.play_arrow, size: 18),
      label: const Text('Process'),
      onPressed: disabled ? null : () => _onProcess(region, _defaultProfile),
      style: TextButton.styleFrom(
        foregroundColor: disabled ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Widget _buildProcessOptionsButton(Region region, {bool disabled = false}) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 20, color: disabled ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary),
      tooltip: 'Process with specific profile',
      enabled: !disabled,
      onSelected: (String value) {
        if (value == 'manage_profiles') {
          _showManageProfilesDialog(context);
        } else {
          final selectedProfile = _profiles.firstWhere((p) => p.id == value, orElse: () => _defaultProfile!);
          _onProcess(region, selectedProfile);
        }
      },
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem<String>(
          value: 'manage_profiles',
          child: ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Manage Profiles'),
            dense: true,
          ),
        ),
        if (_profiles.isNotEmpty) const PopupMenuDivider(),
        ..._profiles.map((profile) => PopupMenuItem<String>(
              value: profile.id,
              child: Text(profile.name + (profile.isDefault ? ' (Default)' : '')),
            )),
      ],
    );
  }
  
  Future<void> _onDownload(Region region) async {
    if (_activeOperations.containsKey(region.name)) return;

    final documentsPath = await _documentsPath;
    final targetFileName = _generateFileName(region.name);
    final targetFilePath = p.join(documentsPath, targetFileName);

    setState(() {
      _activeOperations[region.name] = RegionStatus.downloading;
      _operationProgress[region.name] = 0.0;
      _updateRegionInList(region.copyWith(status: RegionStatus.downloading, progress: 0.0, errorMessage: null, clearErrorMessage: true));
    });

    try {
      await _downloadService.downloadFile(
        region.url,
        targetFilePath,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _operationProgress[region.name] = progress;
              _updateRegionInList(region.copyWith(progress: progress, status: RegionStatus.downloading));
            });
          }
        },
      );

      if (mounted) {
         final updatedRegion = region.copyWith(
            status: RegionStatus.downloaded,
            filePath: targetFilePath,
            progress: 1.0,
            errorMessage: null,
            clearErrorMessage: true
          );
        _updateRegionInList(updatedRegion);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${region.name} downloaded successfully.')));
      }
    } catch (e, s) {
      print('Error downloading ${region.name}: $e\n$s');
      if (mounted) {
        final updatedRegion = region.copyWith(status: RegionStatus.error, errorMessage: e.toString(), progress: 0.0);
        _updateRegionInList(updatedRegion);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed for ${region.name}: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _activeOperations.remove(region.name));
    }
  }

  Future<void> _onDelete(Region region, [bool silent = false]) async {
    if (_activeOperations.containsKey(region.name) && _activeOperations[region.name] != RegionStatus.error) {
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot delete ${region.name} while an operation is in progress.')));
      return;
    }
    
    bool filesDeleted = false;
    try {
      final List<String?> pathsToDelete = [region.filePath, region.processedFilePath];
      for (final path in pathsToDelete) {
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            filesDeleted = true;
            print('Deleted: $path');
          }
        }
      }
      
      final updatedRegion = region.copyWith(
        status: RegionStatus.notDownloaded,
        filePath: null, 
        processedFilePath: null,
        progress: 0.0,
        errorMessage: null,
        clearErrorMessage: true
      );
      _updateRegionInList(updatedRegion);
      
      if (filesDeleted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${region.name} files deleted.')));
      } else if (!filesDeleted && !silent) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No files found to delete for ${region.name}.')));
      }
    } catch (e, s) {
      print('Error deleting files for ${region.name}: $e\n$s');
       if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting files for ${region.name}: ${e.toString()}')));
        _updateRegionInList(region.copyWith(errorMessage: e.toString(), status: RegionStatus.error));
      }
    } finally {
       if (mounted) setState(() => _activeOperations.remove(region.name));
    }
  }

  void _onRedownload(Region region) async {
    await _onDelete(region, true); 
    _onDownload(region);
  }

  void _updateRegionInList(Region updatedRegion) {
    final index = _regions.indexWhere((r) => r.name == updatedRegion.name);
    if (index != -1) setState(() => _regions[index] = updatedRegion);
  }

  Future<void> _onProcess(Region region, Profile? profileToUse) async {
    profileToUse ??= _defaultProfile;

    if (profileToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No profile available for processing. Please create or set a default profile.')));
      final loadedDefaultProfile = await _dbService.getDefaultProfile(); 
        if (mounted) setState(() => _defaultProfile = loadedDefaultProfile);
        if (loadedDefaultProfile == null) {
           _showManageProfilesDialog(context);
           return;
        }
        profileToUse = loadedDefaultProfile;
    }

    if (region.filePath == null || !(await File(region.filePath!).exists())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Original map for ${region.name} not found. Download first.')));
      _updateRegionInList(region.copyWith(status: RegionStatus.error, errorMessage: "Original file missing."));
      return;
    }
    
    if (_activeOperations.containsKey(region.name)) return;

    final sanitizedRegionName = region.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    final sanitizedProfileName = profileToUse.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    final suggestedFileName = '${sanitizedRegionName}_$sanitizedProfileName.mbtiles';

    String? outputFilePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save processed map as...',
      fileName: suggestedFileName,
      type: FileType.custom,
      allowedExtensions: ['mbtiles'],
    );

    if (outputFilePath == null) {
      return;
    }

    if (!outputFilePath.toLowerCase().endsWith('.mbtiles')) {
      outputFilePath = '$outputFilePath.mbtiles';
    }

    setState(() {
      _activeOperations[region.name] = RegionStatus.processing;
      _operationProgress[region.name] = 0.0;
      _updateRegionInList(region.copyWith(status: RegionStatus.processing, progress: 0.0, errorMessage: null, clearErrorMessage: true));
    });

    try {
      await _mbtilesService.processMBTiles(
        region.filePath!,
        outputFilePath,
        profile: profileToUse,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _operationProgress[region.name] = progress;
              _updateRegionInList(region.copyWith(progress: progress, status: RegionStatus.processing));
            });
          }
        },
      );

      if (mounted) {
        final updatedRegion = region.copyWith(
          status: RegionStatus.processed,
          processedFilePath: outputFilePath,
          lastUsedProfileId: profileToUse.id,
          progress: 1.0,
          errorMessage: null,
          clearErrorMessage: true
        );
        _updateRegionInList(updatedRegion);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${region.name} processed with ${profileToUse.name} and saved to ${p.basename(outputFilePath)}.')));
      }
    } catch (e, s) {
      print('Error processing ${region.name}: $e\n$s');
      if (mounted) {
         final updatedRegion = region.copyWith(status: RegionStatus.error, errorMessage: e.toString(), progress: 0.0);
        _updateRegionInList(updatedRegion);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Processing failed for ${region.name}: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _activeOperations.remove(region.name));
    }
  }

  // Renamed from _showProfileEditor
  Future<void> _showEditProfileDialog(BuildContext context, [Profile? existingProfile]) async {
    final formKey = GlobalKey<FormState>();
    String profileName = existingProfile?.name ?? '';
    Map<String, bool> layerSelections = {};
    List<String> allKnownLayers = MBTilesService.publicLayerDescriptions.keys.toList();

    allKnownLayers.sort(); 

    if (existingProfile != null) {
      for (var layer in allKnownLayers) {
        layerSelections[layer] = existingProfile.layersToKeep.contains(layer);
      }
    } else {
       for (var layer in allKnownLayers) {
        layerSelections[layer] = !MBTilesService.defaultLayersToNotKeep.contains(layer);
      }
    }
    
    bool isDefault = existingProfile?.isDefault ?? false;
    final originalIsDefault = existingProfile?.isDefault ?? false;
    final originalProfileId = existingProfile?.id;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingProfile == null ? 'Create New Profile' : 'Edit Profile "${existingProfile.name}"'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: ListBody(
                    children: <Widget>[
                      TextFormField(
                        initialValue: profileName,
                        decoration: const InputDecoration(labelText: 'Profile Name', border: OutlineInputBorder()),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Profile name cannot be empty';
                          // Check for uniqueness only if name changed or it's a new profile
                          if (_profiles.any((p) => p.name.toLowerCase() == value.trim().toLowerCase() && p.id != originalProfileId)) {
                            return 'Profile name already exists';
                          }
                          return null;
                        },
                        onSaved: (value) => profileName = value!.trim(),
                      ),
                      const SizedBox(height: 20),
                      Text('Layers to Keep:', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.35,
                        width: MediaQuery.of(context).size.width * 0.8,
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                          child: ListView.builder(
                            itemCount: allKnownLayers.length,
                            itemBuilder: (context, index) {
                              final layerName = allKnownLayers[index];
                              return CheckboxListTile(
                                title: Text(layerName.replaceAll('_', ' ').split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() + e.substring(1) : '').join(' ')),
                                subtitle: Text(MBTilesService.publicLayerDescriptions[layerName] ?? 'No description', style: const TextStyle(fontSize: 11)),
                                value: layerSelections[layerName] ?? false,
                                onChanged: (bool? value) => setDialogState(() => layerSelections[layerName] = value ?? false),
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Set as Default Profile'),
                        value: isDefault,
                        onChanged: (bool? value) => setDialogState(() => isDefault = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
                ElevatedButton(
                  child: const Text('Save Profile'),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      formKey.currentState!.save();
                      final List<String> layersToKeepForProfile = layerSelections.entries.where((e) => e.value).map((e) => e.key).toList();
                      Profile profileToSave;

                      if (existingProfile != null) {
                        profileToSave = Profile(id: existingProfile.id, name: profileName, layersToKeep: layersToKeepForProfile, isDefault: isDefault);
                        await _dbService.updateProfile(profileToSave);
                      } else {
                        profileToSave = Profile(id: DateTime.now().millisecondsSinceEpoch.toString(), name: profileName, layersToKeep: layersToKeepForProfile, isDefault: isDefault);
                        await _dbService.insertProfile(profileToSave);
                      }

                      // Handle default profile logic
                      if (isDefault && (existingProfile == null || !originalIsDefault || existingProfile.id != profileToSave.id)) {
                        await _dbService.setDefaultProfile(profileToSave.id);
                      } else if (!isDefault && originalIsDefault) {
                         // If this was the default and is no longer, ensure another default exists or make this one default again if it's the only one.
                         final otherDefaults = await _dbService.getAllProfiles().then((list) => list.where((p) => p.isDefault && p.id != profileToSave.id));
                         if(otherDefaults.isEmpty) { 
                            // If unsetting default leaves no default, and there are profiles, re-set this one or the first one.
                            // For simplicity, if it's the only profile, it must be default.
                            final allProfilesAfterSave = await _dbService.getAllProfiles();
                            if (allProfilesAfterSave.length == 1 && allProfilesAfterSave.first.id == profileToSave.id) {
                                await _dbService.setDefaultProfile(profileToSave.id);
                            } else if (allProfilesAfterSave.isNotEmpty && allProfilesAfterSave.first.id != profileToSave.id) {
                                // If there are other profiles, make the first one default (or implement more complex logic)
                                // For now, let's ensure *this* one becomes default if it was the only one being made non-default
                                // and no other default was set. This logic might need refinement based on desired UX.
                                // A simpler approach: if unsetting default and no other default exists, re-set this one.
                                await _dbService.setDefaultProfile(profileToSave.id); 
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('"${profileToSave.name}" was kept as default as it is the only profile or no other default was set.'))
                                );
                            } else if (allProfilesAfterSave.isEmpty) {
                                // This case should ideally not happen if we ensure one default always.
                                // But if it does, the next ensureValidDefaultProfile will handle it.
                            }
                         }
                      }
                      
                      await _loadInitialData(); // Reload all data to reflect changes
                      Navigator.of(dialogContext).pop(); // Close the edit/create dialog
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile "${profileToSave.name}" saved.')));
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  // New dialog to manage all profiles
  Future<void> _showManageProfilesDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        // Use a StatefulBuilder to allow updating the list after delete/edit
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Profiles'),
              content: SizedBox(
                width: double.maxFinite,
                child: _profiles.isEmpty
                    ? const Center(child: Text('No profiles created yet.'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _profiles.length,
                        itemBuilder: (context, index) {
                          final profile = _profiles[index];
                          return ListTile(
                            title: Text(profile.name + (profile.isDefault ? ' (Default)' : '')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  tooltip: 'Edit ${profile.name}',
                                  onPressed: () async {
                                    Navigator.of(dialogContext).pop(); // Close manage dialog first
                                    await _showEditProfileDialog(this.context, profile); // Show edit dialog
                                    // No need to call _loadInitialData here as _showEditProfileDialog does it.
                                    // setDialogState(() {}); // Refresh the list in manage dialog if it were still open
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red.shade700),
                                  tooltip: 'Delete ${profile.name}',
                                  onPressed: () async {
                                    final confirmDelete = await showDialog<bool>(
                                      context: this.context, // Use the main screen's context for confirmation
                                      builder: (BuildContext confirmDialogContext) => AlertDialog(
                                        title: Text('Delete Profile "${profile.name}"?'),
                                        content: const Text('This action cannot be undone.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.of(confirmDialogContext).pop(false), child: const Text('Cancel')),
                                          TextButton(
                                            onPressed: () => Navigator.of(confirmDialogContext).pop(true),
                                            child: Text('Delete', style: TextStyle(color: Colors.red.shade700)),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmDelete == true) {
                                      await _dbService.deleteProfile(profile.id);
                                      await _dbService.ensureValidDefaultProfile(); // Ensure a default profile exists
                                      await _loadInitialData(); // Reload data
                                      setDialogState(() {}); 
                                      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Profile "${profile.name}" deleted.')));
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Profile'),
                  onPressed: () async {
                     Navigator.of(dialogContext).pop();
                    await _showEditProfileDialog(this.context);
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }
}
