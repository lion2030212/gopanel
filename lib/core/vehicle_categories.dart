class VehicleCategories {
  static const labels = <String, String>{
    'standard': 'GoFast سوزوكي',
    'comfort': 'GoTalabat دليفيرى',
    'scooter': 'GoScooter المنجز',
  };

  static String labelFor(Object? category) {
    final value = category?.toString();
    return labels[value] ?? value ?? 'غير متوفر';
  }
}