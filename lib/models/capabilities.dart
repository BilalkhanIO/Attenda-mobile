class Capabilities {
  final Map<String, bool> features;
  final List<String> permissions;

  Capabilities({
    required this.features,
    required this.permissions,
  });

  factory Capabilities.fromJson(Map<String, dynamic> json) {
    return Capabilities(
      features: Map<String, bool>.from(json['features'] ?? {}),
      permissions: List<String>.from(json['permissions'] ?? []),
    );
  }

  bool hasFeature(String feature) {
    return features[feature] == true;
  }

  bool hasPermission(String permission) {
    return permissions.contains(permission);
  }
}
