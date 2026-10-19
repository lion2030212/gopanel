import 'package:flutter/material.dart';

class MapMarkerDetailsCard extends StatelessWidget {
  const MapMarkerDetailsCard({
    required this.role,
    required this.name,
    required this.phone,
    required this.status,
    required this.updatedAt,
    required this.statusColor,
    required this.onDismiss,
    super.key,
  });

  final String role;
  final String? name;
  final String? phone;
  final String status;
  final String updatedAt;
  final Color statusColor;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final displayName = name?.trim();
    final displayPhone = phone?.trim();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        elevation: 6,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      role,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              _DetailRow(
                label: 'الاسم',
                value: displayName == null || displayName.isEmpty
                    ? 'غير متوفر'
                    : displayName,
              ),
              _DetailRow(
                label: 'الجوال',
                value: displayPhone == null || displayPhone.isEmpty
                    ? 'غير متوفر'
                    : displayPhone,
                valueDirection: TextDirection.ltr,
              ),
              _DetailRow(
                label: 'الحالة',
                value: status,
                valueColor: statusColor,
              ),
              _DetailRow(
                label: 'آخر تحديث',
                value: updatedAt,
                valueDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueDirection,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final TextDirection? valueDirection;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Directionality(
                textDirection: valueDirection ?? TextDirection.rtl,
                child: Text(
                  value,
                  textAlign: valueDirection == TextDirection.ltr
                      ? TextAlign.left
                      : TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: valueColor,
                        fontWeight: valueColor == null ? null : FontWeight.w600,
                      ),
                ),
              ),
            ),
          ],
        ),
      );
}