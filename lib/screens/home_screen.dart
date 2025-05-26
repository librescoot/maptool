import 'package:flutter/material.dart';
import '../models/region.dart';
import '../services/geofabrik_service.dart';
import 'region_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GeofabrikService _geofabrikService = GeofabrikService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Region> _regions = [];

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('Fetching regions from Geofabrik...');
      final regions = await _geofabrikService.fetchRegions();
      print('Fetched ${regions.length} regions');
      
      setState(() {
        _regions = regions;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching regions: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MapTool'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
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
                onPressed: _loadRegions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_regions.isEmpty) {
      return const Center(
        child: Text('No regions found'),
      );
    }

    return ListView.builder(
      itemCount: _regions.length,
      itemBuilder: (context, index) {
        final region = _regions[index];
        return ListTile(
          title: Text(region.name),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegionDetailScreen(region: region),
              ),
            );
          },
        );
      },
    );
  }
}
