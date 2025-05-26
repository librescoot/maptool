import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
// import 'package:file_picker/file_picker.dart'; // Will be needed later

import '../models/region.dart';
import '../models/profile.dart';
import '../services/geofabrik_service.dart';
import '../services/database_service.dart';
import '../services/download_service.dart';
import '../services/mbtiles_service.dart';
// import 'region_detail_screen.dart'; // To be removed

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

  // To track active operations for specific regions
  final Map<String, RegionStatus> _activeOperations = {}; // region.name -> status
  final Map<String, double> _operationProgress = {}; // region.name -> progress

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
      // Load profiles first
      final profiles = await _dbService.getAllProfiles();
      final defaultProfile = await _dbService.getDefaultProfile();
      
      // Load static region data
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
          currentFilePath = processedFilePath; // Prefer processed if available
        } else if (originalExists) {
          status = RegionStatus.downloaded;
        }
        
        enrichedRegions.add(
          staticRegion.copyWith(
            filePath: currentFilePath, // This might be original or processed path
            processedFilePath: processedExists ? processedFilePath : null,
            status: status,
            progress: (status == RegionStatus.downloaded || status == RegionStatus.processed) ? 1.0 : 0.0,
            // sizeMB is not available from static data and not fetched
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
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingRegions || _isLoadingProfiles ? null : _loadInitialData,
            tooltip: 'Refresh Data',
          )
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProfileEditor(context),
        tooltip: 'Manage Profiles',
        child: const Icon(Icons.list_alt_outlined),
      ),
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
              ElevatedButton(
                onPressed: _loadInitialData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_regions.isEmpty) {
      return const Center(
        child: Text('No regions found. Check GeofabrikService.'),
      );
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
    // Determine current status and progress for this specific region
    final currentStatus = _activeOperations[region.name] ?? region.status;
    final currentProgress = _operationProgress[region.name] ?? region.progress;

    List<Widget> actionButtons = [];

    // Action Buttons
    switch (currentStatus) {
      case RegionStatus.notDownloaded:
      case RegionStatus.error:
        actionButtons.add(
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            onPressed: () => _onDownload(region),
          )
        );
        if (region.filePath != null || region.processedFilePath != null) {
          // If there are remnants of files even in error or notDownloaded state (e.g. partial)
          actionButtons.add(const SizedBox(width: 8));
          actionButtons.add(
            TextButton.icon(
              icon: Icon(Icons.delete_forever, color: Colors.grey[700]),
              label: Text('Cleanup Files', style: TextStyle(color: Colors.grey[700])),
              onPressed: () => _onDelete(region, true), // true for silent cleanup
            )
          );
        }
        break;
      case RegionStatus.downloading:
        actionButtons.add(SizedBox(
          height: 36, // Match ElevatedButton default height
          child: OutlinedButton.icon(
            icon: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: currentProgress > 0 ? currentProgress : null)),
            label: Text('Downloading ${ (currentProgress * 100).toStringAsFixed(0) }%'),
            onPressed: null, // TODO: Implement cancel
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ));
        break;
      case RegionStatus.downloaded:
        actionButtons.addAll([
          // For Delete, using PopupMenuButton on Redownload for now
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'redownload') {
                _onRedownload(region);
              } else if (value == 'delete') {
                _onDelete(region);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'redownload',
                child: ListTile(leading: Icon(Icons.refresh), title: Text('Redownload')),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete), title: Text('Delete')),
              ),
            ],
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Redownload'),
              onPressed: null, // onPressed is handled by PopupMenuButton logic
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ),
          const SizedBox(width: 8),
          _buildProcessSplitButton(region, isProcessed: false),
        ]);
        break;
      case RegionStatus.processing:
         actionButtons.add(SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            icon: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: currentProgress > 0 ? currentProgress : null)),
            label: Text('Processing ${ (currentProgress * 100).toStringAsFixed(0) }%'),
            onPressed: null, // TODO: Implement cancel
             style: OutlinedButton.styleFrom(
              disabledForegroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ));
        break;
      case RegionStatus.processed:
         actionButtons.addAll([
            PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'redownload') {
                _onRedownload(region);
              } else if (value == 'delete') {
                _onDelete(region);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'redownload',
                child: ListTile(leading: Icon(Icons.refresh), title: Text('Redownload')),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete), title: Text('Delete')),
              ),
            ],
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Redownload'),
              onPressed: null, 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ),
          const SizedBox(width: 8),
          _buildProcessSplitButton(region, isProcessed: true),
        ]);
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    region.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // Display file size if available (currently not)
                // if (region.sizeMB != null) Text('${region.sizeMB!.toStringAsFixed(1)} MB'),
              ],
            ),
            if (region.errorMessage != null && currentStatus == RegionStatus.error)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Error: ${region.errorMessage}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            // const SizedBox(height: 8), // Space before progress bar
            // Redundant LinearProgressIndicator removed as per feedback
            // if (currentStatus == RegionStatus.downloading || currentStatus == RegionStatus.processing)
            //   Padding(
            //     padding: const EdgeInsets.symmetric(vertical: 4.0),
            //     child: LinearProgressIndicator(
            //       value: currentProgress,
            //       minHeight: 6,
            //     ),
            //   ),
            const SizedBox(height: 8), // Keep some spacing before buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actionButtons,
            ),
          ],
        ),
      ),
    );
  }

  
  Future<void> _onDownload(Region region) async {
    if (_activeOperations.containsKey(region.name)) return; // Already an operation

    final documentsPath = await _documentsPath;
    final targetFileName = _generateFileName(region.name);
    final targetFilePath = p.join(documentsPath, targetFileName);

    setState(() {
      _activeOperations[region.name] = RegionStatus.downloading;
      _operationProgress[region.name] = 0.0;
      // Update the specific region in the list to reflect the change immediately
      _updateRegionInList(region.copyWith(status: RegionStatus.downloading, progress: 0.0, errorMessage: null, clearErrorMessage: true));
    });

    try {
      await _downloadService.downloadFile(
        region.url,
        targetFilePath, // DownloadService needs to accept full path
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _operationProgress[region.name] = progress;
               // Visually update progress in the list item
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${region.name} downloaded successfully.')),
        );
      }
    } catch (e, s) {
      print('Error downloading ${region.name}: $e\n$s');
      if (mounted) {
        final updatedRegion = region.copyWith(
            status: RegionStatus.error,
            errorMessage: e.toString(),
            progress: 0.0
          );
        _updateRegionInList(updatedRegion);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed for ${region.name}: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeOperations.remove(region.name);
          // _operationProgress.remove(region.name); // Keep progress for display until next action
        });
      }
    }
  }

  Future<void> _onDelete(Region region, [bool silent = false]) async {
    if (_activeOperations.containsKey(region.name) && _activeOperations[region.name] != RegionStatus.error) {
      if (!silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot delete ${region.name} while an operation is in progress.')));
      return;
    }
    
    bool filesDeleted = false;
    try {
      if (region.filePath != null) {
        final file = File(region.filePath!);
        if (await file.exists()) {
          await file.delete();
          filesDeleted = true;
          print('Deleted: ${region.filePath}');
        }
      }
      if (region.processedFilePath != null) {
        final file = File(region.processedFilePath!);
        if (await file.exists()) {
          await file.delete();
          filesDeleted = true;
          print('Deleted: ${region.processedFilePath}');
        }
      }

      final updatedRegion = region.copyWith(
        status: RegionStatus.notDownloaded,
        filePath: null,
        processedFilePath: null,
        clearProcessedFilePath: true, // Explicitly nullify
        progress: 0.0,
        errorMessage: null,
        clearErrorMessage: true
      );
      _updateRegionInList(updatedRegion);
      
      if (filesDeleted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${region.name} files deleted.')),
        );
      } else if (!filesDeleted && !silent) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No files found to delete for ${region.name}.')),
        );
      }

    } catch (e, s) {
      print('Error deleting files for ${region.name}: $e\n$s');
       if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting files for ${region.name}: ${e.toString()}')),
        );
        // Optionally revert status to error or keep as is for user to see the error message
        _updateRegionInList(region.copyWith(errorMessage: e.toString(), status: RegionStatus.error));
      }
    } finally {
       if (mounted) {
        setState(() { // General refresh to ensure UI consistency
          _activeOperations.remove(region.name);
        });
      }
    }
  }

  void _onRedownload(Region region) async {
    // First, delete existing files silently.
    await _onDelete(region, true); 
    // Then, start download.
    _onDownload(region);
  }

  // Helper to update a region in the _regions list and trigger UI update
  void _updateRegionInList(Region updatedRegion) {
    final index = _regions.indexWhere((r) => r.name == updatedRegion.name);
    if (index != -1) {
      setState(() {
        _regions[index] = updatedRegion;
      });
    }
  }

  Future<void> _onProcess(Region region, Profile? profileToUse) async {
    if (profileToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile selected for processing. Please select or create a profile.')),
      );
      // Attempt to load default profile if somehow null
      if (_defaultProfile == null) {
        final loadedDefaultProfile = await _dbService.getDefaultProfile();
        if (mounted) setState(() => _defaultProfile = loadedDefaultProfile);
        if (loadedDefaultProfile == null) return; // Still no default profile
        profileToUse = loadedDefaultProfile;
      } else {
         profileToUse = _defaultProfile;
      }
      if (profileToUse == null) return; // Should not happen if default exists
    }

    if (region.filePath == null || !(await File(region.filePath!).exists())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Original map file for ${region.name} not found. Please download it first.')),
      );
      _updateRegionInList(region.copyWith(status: RegionStatus.error, errorMessage: "Original file missing for processing."));
      return;
    }
    
    if (_activeOperations.containsKey(region.name)) return; // Already an operation

    final documentsPath = await _documentsPath;
    final outputFileName = _generateFileName(region.name, processed: true);
    final outputFilePath = p.join(documentsPath, outputFileName);

    setState(() {
      _activeOperations[region.name] = RegionStatus.processing;
      _operationProgress[region.name] = 0.0;
      _updateRegionInList(region.copyWith(status: RegionStatus.processing, progress: 0.0, errorMessage: null, clearErrorMessage: true));
    });

    try {
      await _mbtilesService.processMBTiles(
        region.filePath!, // Positional argument for inputFilePath
        outputFilePath,   // Positional argument for outputFilePath
        profile: profileToUse, // Named argument for profile
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${region.name} processed successfully with profile: ${profileToUse.name}.')),
        );
      }
    } catch (e, s) {
      print('Error processing ${region.name}: $e\n$s');
      if (mounted) {
         final updatedRegion = region.copyWith(
            status: RegionStatus.error,
            errorMessage: e.toString(),
            progress: 0.0
          );
        _updateRegionInList(updatedRegion);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processing failed for ${region.name}: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeOperations.remove(region.name);
        });
      }
    }
  }

  Future<void> _showProfileEditor(BuildContext context, [Profile? existingProfile]) async {
    final _formKey = GlobalKey<FormState>();
    String profileName = existingProfile?.name ?? '';
    // Initialize layersToKeep based on existingProfile or default to all layers from MBTilesService.publicLayerDescriptions
    // For a new profile, a common default might be to keep all known layers initially.
    Map<String, bool> layerSelections = {};
    List<String> allKnownLayers = MBTilesService.publicLayerDescriptions.keys.toList();

    if (existingProfile != null) {
      for (var layer in allKnownLayers) {
        layerSelections[layer] = existingProfile.layersToKeep.contains(layer);
      }
    } else { // New profile: default to keeping all layers that are not in defaultLayersToNotKeep
       for (var layer in allKnownLayers) {
        layerSelections[layer] = !MBTilesService.defaultLayersToNotKeep.contains(layer);
      }
    }
    
    bool isDefault = existingProfile?.isDefault ?? false;
    final originalIsDefault = existingProfile?.isDefault ?? false;
    final originalProfileId = existingProfile?.id;

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button!
      builder: (BuildContext dialogContext) {
        return StatefulBuilder( // Needed for checkboxes inside dialog
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingProfile == null ? 'Create New Profile' : 'Edit Profile'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: ListBody(
                    children: <Widget>[
                      TextFormField(
                        initialValue: profileName,
                        decoration: const InputDecoration(labelText: 'Profile Name'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Profile name cannot be empty';
                          }
                          // Check for duplicate names (excluding current profile if editing)
                          if (_profiles.any((p) => p.name.toLowerCase() == value.trim().toLowerCase() && p.id != originalProfileId)) {
                            return 'Profile name already exists';
                          }
                          return null;
                        },
                        onSaved: (value) => profileName = value!.trim(),
                      ),
                      const SizedBox(height: 16),
                      Text('Layers to Keep:', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allKnownLayers.length,
                          itemBuilder: (context, index) {
                            final layerName = allKnownLayers[index];
                            return CheckboxListTile(
                              title: Text(
                                layerName.replaceAll('_', ' ').split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() + e.substring(1) : '').join(' '),
                                style: const TextStyle(fontSize: 14)
                              ),
                              subtitle: Text(
                                MBTilesService.publicLayerDescriptions[layerName] ?? 'No description',
                                style: const TextStyle(fontSize: 12)
                              ),
                              value: layerSelections[layerName] ?? false,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  layerSelections[layerName] = value ?? false;
                                });
                              },
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Set as Default Profile'),
                        value: isDefault,
                        onChanged: (bool? value) {
                          setDialogState(() {
                            isDefault = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                ElevatedButton(
                  child: const Text('Save Profile'),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();
                      
                      final List<String> layersToKeepForProfile = layerSelections.entries
                          .where((entry) => entry.value)
                          .map((entry) => entry.key)
                          .toList();

                      Profile profileToSave;
                      if (existingProfile != null) {
                        profileToSave = Profile(
                          id: existingProfile.id,
                          name: profileName,
                          layersToKeep: layersToKeepForProfile,
                          isDefault: isDefault,
                        );
                        await _dbService.updateProfile(profileToSave);
                      } else {
                        profileToSave = Profile(
                          id: DateTime.now().millisecondsSinceEpoch.toString(), // Simple unique ID
                          name: profileName,
                          layersToKeep: layersToKeepForProfile,
                          isDefault: isDefault,
                        );
                        await _dbService.insertProfile(profileToSave);
                      }

                      if (isDefault && (existingProfile == null || !originalIsDefault || existingProfile.id != profileToSave.id)) {
                        await _dbService.setDefaultProfile(profileToSave.id);
                      } else if (!isDefault && originalIsDefault && _profiles.where((p) => p.isDefault && p.id != profileToSave.id).isEmpty) {
                        // If unsetting the only default, try to set another profile as default or clear default status
                        // For simplicity, if unsetting the only default, no other profile becomes default automatically here.
                        // This might need more robust logic if a default is strictly required.
                        // For now, if it was default and is no longer, and no other is default, it just means no default.
                        // The DatabaseService.setDefaultProfile handles unsetting other defaults if a new one is set.
                        if (originalIsDefault) { // if it was default and now it's not
                           // if no other profile is default, then the current default profile becomes null
                           final otherDefaults = await _dbService.getAllProfiles().then((list) => list.where((p) => p.isDefault && p.id != profileToSave.id));
                           if(otherDefaults.isEmpty) {
                               // This means we are unchecking the only default profile.
                               // We might want to ensure at least one default, or handle null default profile.
                               // For now, we allow no default profile.
                           }
                        }
                      }
                      
                      await _loadInitialData(); // Reload all data to reflect changes
                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Profile "${profileToSave.name}" saved.')),
                      );
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

  Widget _buildProcessSplitButton(Region region, {required bool isProcessed}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ElevatedButton.icon(
          icon: const Icon(Icons.settings_applications),
          label: Text(isProcessed ? 'Re-Process' : 'Process'),
          onPressed: () => _onProcess(region, _defaultProfile),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Adjust padding
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
          ),
        ),
        Container(
          color: Theme.of(context).buttonTheme.colorScheme?.primaryContainer ?? Theme.of(context).primaryColorDark, // Match button color or use a divider color
          width: 1, // Divider width
          height: 36, // Match button height
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white), // Ensure icon is visible on button
          tooltip: 'More processing options',
          onSelected: (String value) {
            if (value == 'manage_profiles') {
              _showProfileEditor(context); // Opens editor for new/managing profiles
            } else if (value == 'process_with') {
              _showProcessWithProfilePicker(context, region);
            } else {
              // Handle direct profile selection if implemented
              final selectedProfile = _profiles.firstWhere((p) => p.id == value, orElse: () => _defaultProfile!); // Fallback to default
              _onProcess(region, selectedProfile);
            }
          },
          itemBuilder: (BuildContext context) {
            List<PopupMenuEntry<String>> items = [];
            items.add(
              const PopupMenuItem<String>(
                value: 'manage_profiles',
                child: ListTile(leading: Icon(Icons.edit_note), title: Text('Manage Profiles')),
              ),
            );
            items.add(
              const PopupMenuItem<String>(
                value: 'process_with',
                child: ListTile(leading: Icon(Icons.playlist_play), title: Text('Process with...')),
              ),
            );
            if (_profiles.isNotEmpty) {
              items.add(const PopupMenuDivider());
              for (var profile in _profiles) {
                items.add(
                  PopupMenuItem<String>(
                    value: profile.id,
                    child: Text(profile.name + (profile.isDefault ? ' (Default)' : '')),
                  ),
                );
              }
            }
            return items;
          },
           style: ElevatedButton.styleFrom(
             backgroundColor: Theme.of(context).colorScheme.primary, // Match button color
             padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
             shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
           ),
        ),
      ],
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
