import '../models/region.dart';

class GeofabrikService {
  static const String baseUrl = 'https://download.geofabrik.de';

  Future<List<Region>> fetchRegions() async {
    // Hardcoded list of German regions
    return [
      Region(name: 'Baden-Württemberg', url: '$baseUrl/europe/germany/baden-wuerttemberg-shortbread-1.0.mbtiles'),
      Region(name: 'Bayern', url: '$baseUrl/europe/germany/bayern-shortbread-1.0.mbtiles'),
      Region(name: 'Berlin', url: '$baseUrl/europe/germany/berlin-shortbread-1.0.mbtiles'),
      Region(name: 'Brandenburg (inkl. Berlin)', url: '$baseUrl/europe/germany/brandenburg-shortbread-1.0.mbtiles'),
      Region(name: 'Bremen', url: '$baseUrl/europe/germany/bremen-shortbread-1.0.mbtiles'),
      Region(name: 'Hamburg', url: '$baseUrl/europe/germany/hamburg-shortbread-1.0.mbtiles'),
      Region(name: 'Hessen', url: '$baseUrl/europe/germany/hessen-shortbread-1.0.mbtiles'),
      Region(name: 'Mecklenburg-Vorpommern', url: '$baseUrl/europe/germany/mecklenburg-vorpommern-shortbread-1.0.mbtiles'),
      Region(name: 'Niedersachsen', url: '$baseUrl/europe/germany/niedersachsen-shortbread-1.0.mbtiles'),
      Region(name: 'Nordrhein-Westfalen', url: '$baseUrl/europe/germany/nordrhein-westfalen-shortbread-1.0.mbtiles'),
      Region(name: 'Rheinland-Pfalz', url: '$baseUrl/europe/germany/rheinland-pfalz-shortbread-1.0.mbtiles'),
      Region(name: 'Saarland', url: '$baseUrl/europe/germany/saarland-shortbread-1.0.mbtiles'),
      Region(name: 'Sachsen', url: '$baseUrl/europe/germany/sachsen-shortbread-1.0.mbtiles'),
      Region(name: 'Sachsen-Anhalt', url: '$baseUrl/europe/germany/sachsen-anhalt-shortbread-1.0.mbtiles'),
      Region(name: 'Schleswig-Holstein', url: '$baseUrl/europe/germany/schleswig-holstein-shortbread-1.0.mbtiles'),
      Region(name: 'Thüringen', url: '$baseUrl/europe/germany/thueringen-shortbread-1.0.mbtiles'),
    ];
  }
}