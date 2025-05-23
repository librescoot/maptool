import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import '../models/region.dart';

class GeofabrikService {
  static const String baseUrl = 'https://download.geofabrik.de';

  /// Fetches and parses the regions from the Geofabrik download page
  Future<List<Region>> fetchRegions() async {
    try {
      final response = await http.get(Uri.parse(baseUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load regions, status code: ${response.statusCode}');
      }
      
      print('Response body length: ${response.body.length}');
      print('Response body contains #subregions: ${response.body.contains('id="subregions"')}');
      
      // If response body contains the expected subregions table, parse it
      if (response.body.contains('id="subregions"')) {
        return _parseRegions(response.body, baseUrl);
      } else {
        // If not, try to fetch the index.html explicitly
        final indexResponse = await http.get(Uri.parse('$baseUrl/index.html'));
        
        if (indexResponse.statusCode != 200) {
          throw Exception('Failed to load index page, status code: ${indexResponse.statusCode}');
        }
        
        return _parseRegions(indexResponse.body, baseUrl);
      }
    } catch (e) {
      if (e is SocketException) {
        throw Exception('Network error: Could not connect to Geofabrik. Check your internet connection and app permissions. Error: ${e.message}');
      } else if (e is HttpException) {
        throw Exception('HTTP error: ${e.message}. Check app network permissions.');
      } else {
        throw Exception('Error fetching regions: $e');
      }
    }
  }

  /// Fetches and parses subregions from a specific region URL
  Future<List<Region>> fetchSubRegions(String url) async {
    try {
      // Handle URLs that might end with .html or /
      String fetchUrl;
      
      if (url.endsWith('.html')) {
        // If URL already ends with .html, use it directly
        fetchUrl = url;
      } else if (url.endsWith('/')) {
        // If URL ends with /, append index.html
        fetchUrl = '${url}index.html';
      } else if (url.endsWith('.osm.pbf') || url.contains('.')) {
        // If this is a file URL, get the parent directory
        final lastSlashIndex = url.lastIndexOf('/');
        if (lastSlashIndex != -1) {
          final parentDir = url.substring(0, lastSlashIndex + 1);
          fetchUrl = '${parentDir}index.html';
        } else {
          // Fallback
          fetchUrl = '$url.html';
        }
      } else {
        // Otherwise, append .html
        fetchUrl = '$url.html';
      }
      
      print('Fetching subregions from URL: $fetchUrl');
      final response = await http.get(Uri.parse(fetchUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load subregions, status code: ${response.statusCode}');
      }
      
      print('Subregion response body length: ${response.body.length}');
      print('Subregion response contains #subregions: ${response.body.contains('id="subregions"')}');
      
      // Make sure we use the correct parent URL for relative links
      String parentUrl;
      if (fetchUrl.endsWith('.html')) {
        final lastSlash = fetchUrl.lastIndexOf('/');
        parentUrl = lastSlash != -1 ? fetchUrl.substring(0, lastSlash + 1) : '$fetchUrl/';
      } else if (fetchUrl.endsWith('/')) {
        parentUrl = fetchUrl;
      } else {
        parentUrl = '$fetchUrl/';
      }
      
      print('Using parent URL for relative links: $parentUrl');
      return _parseRegions(response.body, parentUrl);
    } catch (e) {
      if (e is SocketException) {
        throw Exception('Network error: Could not connect to server. Check your internet connection and app permissions. Error: ${e.message}');
      } else if (e is HttpException) {
        throw Exception('HTTP error: ${e.message}. Check app network permissions.');
      } else {
        throw Exception('Error fetching subregions: $e');
      }
    }
  }

  /// Helper method to find the shortbread tile package link in an HTML page
  String? _findShortbreadLink(dom.Document document, String parentUrl) {
    // Extract base URL without the HTML file
    String baseUrl = parentUrl;
    if (baseUrl.endsWith('.html')) {
      baseUrl = baseUrl.substring(0, baseUrl.lastIndexOf('/') + 1);
    } else if (!baseUrl.endsWith('/')) {
      baseUrl = '$baseUrl/';
    }
    
    print('Using base URL for shortbread links: $baseUrl');
    
    // First try to find experimental links that mention shortbread
    final listItems = document.querySelectorAll('li');
    
    for (final item in listItems) {
      final content = item.text.toLowerCase();
      if (content.contains('experimental') && content.contains('shortbread')) {
        final links = item.querySelectorAll('a');
        for (final link in links) {
          final href = link.attributes['href'];
          if (href != null && href.endsWith('.mbtiles')) {
            return href.startsWith('http') 
                ? href 
                : _constructUrl(baseUrl, href);
          }
        }
      }
    }
    
    // If not found in list items, try to find by searching for .mbtiles files with shortbread in the name
    final allLinks = document.querySelectorAll('a');
    for (final link in allLinks) {
      final href = link.attributes['href'];
      if (href != null && 
          (href.toLowerCase().contains('shortbread') && href.endsWith('.mbtiles'))) {
        return href.startsWith('http') 
            ? href 
            : _constructUrl(baseUrl, href);
      }
    }
    
    return null;
  }

  /// Parses HTML content to extract regions
  List<Region> _parseRegions(String htmlContent, String parentUrl) {
    final document = html.parse(htmlContent);
    final regions = <Region>[];
    
    // Look for shortbread link on the current page
    final shortbreadUrl = _findShortbreadLink(document, parentUrl);
    if (shortbreadUrl != null) {
      print('Found shortbread URL on page: $shortbreadUrl');
    }
    
    // Try to find the specific subregions table - for region pages this will have a header row with "Sub Region"
    final subregionTables = document.querySelectorAll('table#subregions');
    
    for (final table in subregionTables) {
      // Check if this is the subregions table and not the file details table
      final headers = table.querySelectorAll('th');
      bool isSubregionsTable = false;
      
      for (final header in headers) {
        final headerText = header.text.trim();
        if (headerText.contains('Sub Region') || headerText.contains('Subregion')) {
          isSubregionsTable = true;
          break;
        }
      }
      
      if (!isSubregionsTable) continue;
      
      // Process the rows in the table
      final rows = table.querySelectorAll('tr');
      
      for (final row in rows) {
        // Skip header rows
        if (row.querySelector('th') != null) continue;
        
        // Find the subregion cell (first td with class "subregion")
        final subregionCell = row.querySelector('td.subregion');
        if (subregionCell == null) continue;
        
        // Find the region link
        final linkElement = subregionCell.querySelector('a');
        if (linkElement == null) continue;
        
        final name = linkElement.text.trim();
        final href = linkElement.attributes['href'];
        
        if (href == null || name.isEmpty) continue;
        
        // Skip entries that are file links (typically end with .osm.pbf, .md5, etc.)
        if (href.contains('.osm.') || 
            href.endsWith('.md5') || 
            href.endsWith('.poly') || 
            href.endsWith('-updates')) {
          continue;
        }
        
        // Construct the full URL for the region
        final url = href.startsWith('http') 
            ? href 
            : _constructUrl(parentUrl, href);
        
        print('Adding region: $name, URL: $url');
        regions.add(Region(
          name: name,
          url: url,
          shortbreadUrl: null, // Will be set when the region page is loaded
        ));
      }
    }
    
    // If no subregions found in the specific table, look through regular tables
    // but only if no regions have been found above
    if (regions.isEmpty) {
      final tables = document.querySelectorAll('table');
      
      for (final table in tables) {
        // Skip the details table
        if (table.attributes['id'] == 'details') continue;
        
        final rows = table.querySelectorAll('tr');
        
        for (final row in rows) {
          // Skip header rows
          if (row.querySelector('th') != null) continue;
          
          final cells = row.querySelectorAll('td');
          if (cells.isEmpty) continue;
          
          // Try to find a link to a subregion
          final linkElements = cells.first.querySelectorAll('a');
          if (linkElements.isEmpty) continue;
          
          final linkElement = linkElements.first;
          final name = linkElement.text.trim();
          final href = linkElement.attributes['href'];
          
          if (href == null || name.isEmpty) continue;
          
          // Skip entries that are file links (typically end with .osm.pbf, .md5, etc.)
          if (href.contains('.osm.') || 
              href.endsWith('.md5') || 
              href.endsWith('.poly') || 
              href.endsWith('-updates')) {
            continue;
          }
          
          // Filter for HTML links and use proper URL construction
          if (href.endsWith('.html') || href.endsWith('/')) {
            final url = href.startsWith('http') 
                ? href 
                : _constructUrl(parentUrl, href);
            
            // Look for MBTiles link in the row
            String? mbtileUrl;
            for (final cell in cells) {
              final links = cell.querySelectorAll('a');
              for (final link in links) {
                final linkText = link.text.trim().toLowerCase();
                final linkHref = link.attributes['href'];
                
                if (linkHref != null && (linkHref.endsWith('.mbtiles') || 
                    (linkText.contains('.mbtiles') && linkHref != null))) {
                  mbtileUrl = linkHref.startsWith('http') 
                      ? linkHref 
                      : _constructUrl(parentUrl, linkHref);
                  break;
                }
              }
              if (mbtileUrl != null) break;
            }
            
            print('Adding region (from general table): $name, URL: $url');
            regions.add(Region(
              name: name,
              url: url,
              mbtileUrl: mbtileUrl,
            ));
          }
        }
      }
    }
    
    // Europe page has a special format - handle it explicitly if needed
    if (regions.isEmpty && parentUrl.contains('europe')) {
      // Look for section with subregions header
      final subregionsHeaders = document.querySelectorAll('h3');
      for (final header in subregionsHeaders) {
        if (header.text.trim().contains('Sub Regions')) {
          // Find the table after this header
          var table = header.nextElementSibling;
          while (table != null && table.localName != 'table') {
            table = table.nextElementSibling;
          }
          
          if (table != null && table.localName == 'table') {
            final rows = table.querySelectorAll('tr');
            
            for (final row in rows) {
              // Skip header rows
              if (row.querySelector('th') != null) continue;
              
              // Find the subregion cell
              final subregionCell = row.querySelector('td.subregion');
              if (subregionCell == null) continue;
              
              // Find the region link
              final linkElement = subregionCell.querySelector('a');
              if (linkElement == null) continue;
              
              final name = linkElement.text.trim();
              final href = linkElement.attributes['href'];
              
              if (href == null || name.isEmpty) continue;
              
              // Construct the full URL for the region
              final url = href.startsWith('http') 
                  ? href 
                  : _constructUrl(parentUrl, href);
              
              print('Adding Europe subregion: $name, URL: $url');
              regions.add(Region(
                name: name,
                url: url,
              ));
            }
          }
        }
      }
    }
    
    return regions;
  }
  
  /// Helper method to properly construct URLs with correct slashes
  String _constructUrl(String baseUrl, String path) {
    // Remove trailing slash from base URL if present
    String base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    
    // Remove leading slash from path if present
    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    
    // Construct URL with a slash between
    return '$base/$cleanPath';
  }

  /// Fetches and parses the region details including shortbread URL
  Future<Region> fetchRegionDetails(Region region) async {
    try {
      // Use the same URL handling as in fetchSubRegions
      String fetchUrl;
      
      if (region.url.endsWith('.html')) {
        fetchUrl = region.url;
      } else if (region.url.endsWith('/')) {
        fetchUrl = '${region.url}index.html';
      } else if (region.url.endsWith('.osm.pbf') || region.url.contains('.')) {
        final lastSlashIndex = region.url.lastIndexOf('/');
        if (lastSlashIndex != -1) {
          final parentDir = region.url.substring(0, lastSlashIndex + 1);
          fetchUrl = '${parentDir}index.html';
        } else {
          fetchUrl = '${region.url}.html';
        }
      } else {
        fetchUrl = '${region.url}.html';
      }
      
      print('Fetching region details from URL: $fetchUrl');
      final response = await http.get(Uri.parse(fetchUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load region details, status code: ${response.statusCode}');
      }
      
      final document = html.parse(response.body);
      final shortbreadUrl = _findShortbreadLink(document, fetchUrl);
      
      if (shortbreadUrl != null) {
        print('Found shortbread URL for ${region.name}: $shortbreadUrl');
      } else {
        print('No shortbread URL found for ${region.name}');
      }
      
      return Region(
        name: region.name,
        url: region.url,
        mbtileUrl: region.mbtileUrl,
        shortbreadUrl: shortbreadUrl,
        subRegions: region.subRegions,
      );
    } catch (e) {
      print('Error fetching region details: $e');
      return region; // Return original region if details fetch fails
    }
  }
} 