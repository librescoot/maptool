// Represents a processing profile for mbtiles.
class Profile {
  String id; // Unique identifier, could be a UUID or a name
  String name; // User-friendly name for the profile
  List<String> layersToKeep; // List of layer names to retain. All other layers will be removed.
  bool isDefault; // Indicates if this is the default profile

  Profile({
    required this.id,
    required this.name,
    this.layersToKeep = const [],
    this.isDefault = false,
  });

  // For database persistence
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'layersToKeep': layersToKeep.join(','), // Store as comma-separated string
      'isDefault': isDefault ? 1 : 0, // Store boolean as int
    };
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'],
      name: map['name'],
      layersToKeep: (map['layersToKeep'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      isDefault: map['isDefault'] == 1,
    );
  }

  @override
  String toString() {
    return 'Profile(id: $id, name: $name, isDefault: $isDefault)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Profile && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
