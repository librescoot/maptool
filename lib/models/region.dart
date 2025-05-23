class Region {
  final String name;
  final String url;
  final String? mbtileUrl;
  final String? shortbreadUrl;
  final List<Region> subRegions;

  Region({
    required this.name, 
    required this.url, 
    this.mbtileUrl, 
    this.shortbreadUrl,
    this.subRegions = const []
  });

  @override
  String toString() {
    return name;
  }
} 