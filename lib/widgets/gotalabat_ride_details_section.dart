import 'dart:typed_data';

import 'package:flutter/material.dart';

bool hasGotalabatOrderDetails(Map<String, dynamic> ride) {
  final description = ride['deliveryDescription']?.toString().trim();
  return description != null && description.isNotEmpty;
}

bool isGotalabatRideField(String key) => const {
      'deliveryDescription',
      'deliveryImageUrl',
      'pickupRegion',
      'pickupLandmark',
      'dropoffRegion',
      'dropoffLandmark',
      'recipientName',
      'recipientPhone',
      'deliveryPayer',
      'deliveryPaymentCollected',
      'deliveryPaymentCollectedAt',
    }.contains(key);

class GotalabatRideDetailsSection extends StatelessWidget {
  const GotalabatRideDetailsSection({
    required this.ride,
    this.imageBytes,
    this.isLoadingImage = false,
    super.key,
  });

  final Map<String, dynamic> ride;
  final Uint8List? imageBytes;
  final bool isLoadingImage;

  @override
  Widget build(BuildContext context) {
    if (!hasGotalabatOrderDetails(ride)) return const SizedBox.shrink();

    final imageUrl = ride['deliveryImageUrl']?.toString().trim();
    final fields = <MapEntry<String, String>>[
      MapEntry('وصف الطلب', _text(ride['deliveryDescription'])),
      MapEntry('منطقة الاستلام', _text(ride['pickupRegion'])),
      MapEntry('معلم الاستلام', _text(ride['pickupLandmark'])),
      MapEntry('منطقة التسليم', _text(ride['dropoffRegion'])),
      MapEntry('معلم التسليم', _text(ride['dropoffLandmark'])),
      MapEntry('اسم المستلم', _text(ride['recipientName'])),
      MapEntry('هاتف المستلم', _text(ride['recipientPhone'])),
      MapEntry('جهة الدفع', _payer(ride['deliveryPayer'])),
      if (ride['deliveryPaymentCollectedAt'] != null)
        const MapEntry('حالة تحصيل الطلب', 'تم الدفع'),
      MapEntry(
        'المبلغ المحصل',
        ride['deliveryPaymentCollected'] == null
            ? ''
            : '${ride['deliveryPaymentCollected']} ج.م',
      ),
      MapEntry('وقت التحصيل', _date(ride['deliveryPaymentCollectedAt'])),
    ].where((field) => field.value.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
          child: Text(
            'تفاصيل طلب GoTalabat',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (imageUrl != null && imageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: isLoadingImage
                  ? const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : imageBytes == null
                      ? _imageFallback(context)
                      : Image.memory(
                          imageBytes!,
                          height: 210,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              _imageFallback(context),
                        ),
            ),
          ),
        ...fields.map((field) => Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 5, 16, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      field.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      field.value,
                      textDirection: field.key == 'هاتف المستلم'
                          ? TextDirection.ltr
                          : null,
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 8),
      ],
    );
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  Widget _imageFallback(BuildContext context) => Container(
        height: 160,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined),
            SizedBox(height: 6),
            Text('تعذر تحميل صورة الطلب'),
          ],
        ),
      );

  String _payer(dynamic value) => switch (value?.toString()) {
        'sender' => 'المرسل',
        'recipient' => 'المستلم',
        _ => '',
      };

  String _date(dynamic value) {
    if (value == null) return '';
    final parsed = value is DateTime ? value : DateTime.tryParse('$value');
    if (parsed == null) return value.toString();
    final local = parsed.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
