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
      // Ensure we have a valid default profile with proper layer selections
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
        String? currentFilePath = originalExists ? originalFilePath : null;

        if (processedExists) {
          status = RegionStatus.processed;
          currentFilePath = processedFilePath;
        } else if (originalExists) {
          status = RegionStatus.downloaded;
        }
        
        enrichedRegions.add(
          staticRegion.copyWith(
            filePath: currentFilePath,
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
            onPressed: () => _showProfileEditor(context),
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
    final bool isOperating = currentStatus == RegionStatus.downloading || currentStatus == RegionStatus.processing;

    List<Widget> buttons = [];
    switch (currentStatus) {
      case RegionStatus.notDownloaded:
      case RegionStatus.error:
        buttons.add(_buildDownloadButton(region));
        if (region.filePath != null || region.processedFilePath != null) {
          buttons.add(const SizedBox(width: 8));
          buttons.add(_buildCleanupFilesButton(region));
        }
        break;
      case RegionStatus.downloading:
        buttons.add(_buildInProgressButton(currentStatus, currentProgress));
        // Show disabled buttons for other actions during download
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildRedownloadSplitButton(region, disabled: true));
        if (region.filePath != null) {
          buttons.add(const SizedBox(width: 8));
          buttons.add(_buildProcessSplitButton(region, isProcessed: false, disabled: true));
        }
        break;
      case RegionStatus.processing:
        // Show disabled buttons for other actions during processing
        buttons.add(_buildRedownloadSplitButton(region, disabled: true));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildInProgressButton(currentStatus, currentProgress));
        break;
      case RegionStatus.downloaded:
        buttons.add(_buildRedownloadSplitButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessSplitButton(region, isProcessed: false));
        break;
      case RegionStatus.processed:
        buttons.add(_buildRedownloadSplitButton(region));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_buildProcessSplitButton(region, isProcessed: true));
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
    return ElevatedButton.icon(
      icon: const Icon(Icons.download, size: 18),
      label: const Text('Download'),
      onPressed: () => _onDownload(region),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
    );
  }
   Widget _buildCleanupFilesButton(Region region) {
    return TextButton.icon(
      icon: Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.grey[700]),
      label: Text('Cleanup', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      onPressed: () => _onDelete(region, true),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
    );
  }


  Widget _buildInProgressButton(RegionStatus status, double progress) {
    String text = status == RegionStatus.downloading ? 'Downloading' : 'Processing';
    // If progress is 0 or 1 (or not available), show indeterminate spinner in button
    // Otherwise, show determinate spinner.
    bool isDeterminate = progress > 0 && progress < 1;
    return OutlinedButton.icon(
      icon: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: isDeterminate ? progress : null)),
      label: Text('$text ${isDeterminate ? (progress * 100).toStringAsFixed(0) + '%' : ''}'),
      onPressed: null, // TODO: Implement cancel
      style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          disabledForegroundColor: Theme.of(context).textTheme.bodySmall?.color),
    );
  }

  Widget _buildSplitButtonBase(
      {required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      required Color backgroundColor,
      required Color foregroundColor,
      required List<PopupMenuEntry<String>> menuItems,
      required PopupMenuItemSelected<String>? onMenuSelected}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ElevatedButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(label),
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
            ),
          ),
        ),
        Container(width: 1, height: 36, color: foregroundColor.withOpacity(0.3)), // Divider
        Material(
          color: backgroundColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
          ),
          child: PopupMenuButton<String>(
            icon: Icon(Icons.arrow_drop_down, color: foregroundColor),
            tooltip: 'More options',
            onSelected: onMenuSelected,
            itemBuilder: (BuildContext context) => menuItems,
            padding: EdgeInsets.zero,
            enabled: onMenuSelected != null && menuItems.isNotEmpty,
          ),
        ),
      ],
    );
  }

  Widget _buildRedownloadSplitButton(Region region, {bool disabled = false}) {
    return _buildSplitButtonBase(
      icon: Icons.refresh,
      label: 'Redownload',
      onPressed: disabled ? null : () => _onRedownload(region),
      backgroundColor: disabled ? Colors.grey : Colors.orange,
      foregroundColor: Colors.white,
      onMenuSelected: disabled ? null : (String value) {
        if (value == 'delete') _onDelete(region);
      },
      menuItems: disabled ? [] : [
        const PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Delete Files'))),
      ],
    );
  }

  Widget _buildProcessSplitButton(Region region, {required bool isProcessed, bool disabled = false}) {
    return _buildSplitButtonBase(
      icon: Icons.settings_applications,
      label: isProcessed ? 'Re-Process' : 'Process',
      onPressed: disabled ? null : () => _onProcess(region, _defaultProfile),
      backgroundColor: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
      onMenuSelected: disabled ? null : (String value) {
        if (value == 'manage_profiles') _showProfileEditor(context);
        else if (value == 'process_with') _showProcessWithProfilePicker(context, region);
        else {
          final selectedProfile = _profiles.firstWhere((p) => p.id == value, orElse: () => _defaultProfile!);
          _onProcess(region, selectedProfile);
        }
      },
      menuItems: disabled ? [] : [
        const PopupMenuItem<String>(value: 'manage_profiles', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Manage Profiles'))),
        const PopupMenuItem<String>(value: 'process_with', child: ListTile(leading: Icon(Icons.playlist_play), title: Text('Process with...'))),
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
        clearProcessedFilePath: true,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No profile available for processing.')));
      final loadedDefaultProfile = await _dbService.getDefaultProfile(); // Try to load/ensure default
        if (mounted) setState(() => _defaultProfile = loadedDefaultProfile);
        if (loadedDefaultProfile == null) {
           _showProfileEditor(context); // Prompt to create one
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

    // Generate suggested filename: RegionName_ProfileName.mbtiles
    final sanitizedRegionName = region.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    final sanitizedProfileName = profileToUse.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');
    final suggestedFileName = '${sanitizedRegionName}_${sanitizedProfileName}.mbtiles';

    // Show file picker to choose save location
    String? outputFilePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save processed map as...',
      fileName: suggestedFileName,
      type: FileType.custom,
      allowedExtensions: ['mbtiles'],
    );

    if (outputFilePath == null) {
      // User cancelled the file picker
      return;
    }

    // Ensure the file has the correct extension
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

  Future<void> _showProfileEditor(BuildContext context, [Profile? existingProfile]) async {
    final formKey = GlobalKey<FormState>();
    String profileName = existingProfile?.name ?? '';
    Map<String, bool> layerSelections = {};
    List<String> allKnownLayers = MBTilesService.publicLayerDescriptions.keys.toList();

    allKnownLayers.sort(); // Sort alphabetically for consistent display

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
                        width: MediaQuery.of(context).size.width * 0.8, // Ensure dialog has reasonable width
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

                      if (isDefault && (existingProfile == null || !originalIsDefault || existingProfile.id != profileToSave.id)) {
                        await _dbService.setDefaultProfile(profileToSave.id);
                      } else if (!isDefault && originalIsDefault) {
                         final otherDefaults = await _dbService.getAllProfiles().then((list) => list.where((p) => p.isDefault && p.id != profileToSave.id));
                         if(otherDefaults.isEmpty && _profiles.length > 1) { // If it was the only default and there are other profiles
                            // Optionally, prompt user to select a new default or auto-select one.
                            // For now, we allow no default if explicitly unset.
                         }
                      }
                      
                      await _loadInitialData();
                      Navigator.of(dialogContext).pop();
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

  Future<void> _showProcessWithProfilePicker(BuildContext context, Region region) async {
    if (_profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profiles available. Please create one first.')),
      );
      _showProfileEditor(context); // Optionally open editor if no profiles exist
      return;
    }

    Profile? selectedProfile = await showDialog<Profile>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Process ${region.name} with:'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _profiles.length,
              itemBuilder: (BuildContext context, int index) {
                final profile = _profiles[index];
                return ListTile(
                  title: Text(profile.name),
                  subtitle: Text('${profile.layersToKeep.length} layers to keep' + (profile.isDefault ? ' (Default)' : '')),
                  onTap: () {
                    Navigator.of(dialogContext).pop(profile);
                  },
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );

    if (selectedProfile != null) {
      _onProcess(region, selectedProfile);
    }
  }
}
