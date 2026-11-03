class MapSearchPresentation {
  static bool matchesIdentity({
    required String query,
    String? name,
    String? phone,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return false;
    final normalizedName = name?.trim().toLowerCase() ?? '';
    final normalizedPhone = normalizePhone(phone ?? '');
    return normalizedName.contains(normalizedQuery) ||
        normalizedPhone.contains(normalizePhone(normalizedQuery));
  }

  static bool matchesRideId({required String query, required int rideId}) {
    return int.tryParse(query.trim()) == rideId;
  }

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '');
}
