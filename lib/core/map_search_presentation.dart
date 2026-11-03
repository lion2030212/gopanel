class MapSearchPresentation {
  static bool matchesIdentity({
    required String query,
    String? name,
    String? phone,
    String? licensePlate,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return false;
    final normalizedName = name?.trim().toLowerCase() ?? '';
    final normalizedPhone = normalizePhone(phone ?? '');
    final normalizedPlateQuery = normalizeLicensePlate(normalizedQuery);
    final normalizedPlate = normalizeLicensePlate(licensePlate ?? '');
    return normalizedName.contains(normalizedQuery) ||
        normalizedPhone.contains(normalizePhone(normalizedQuery)) ||
        (normalizedPlateQuery.isNotEmpty &&
            normalizedPlate.contains(normalizedPlateQuery));
  }

  static bool matchesRideId({required String query, required int rideId}) {
    return int.tryParse(query.trim()) == rideId;
  }

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '');

    static String normalizeLicensePlate(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
}
