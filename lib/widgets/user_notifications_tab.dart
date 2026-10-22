import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

class UserNotificationsTab extends StatefulWidget {
  const UserNotificationsTab({
    required this.notifications,
    super.key,
  });

  final List<Map<String, dynamic>> notifications;

  @override
  State<UserNotificationsTab> createState() => _UserNotificationsTabState();
}

class _UserNotificationsTabState extends State<UserNotificationsTab> {
  static const _categories = <String, String>{
    'customer_service': 'خدمة العملاء',
    'promotion': 'عرض ترويجي',
    'guidance': 'توجيه',
  };

  String _period = 'week';
  String? _selectedCategory;
  DateTimeRange? _customRange;

  DateTimeRange? _periodRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'day':
        return DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      case 'week':
        final daysSinceSaturday = (now.weekday + 1) % 7;
        final weekStart = today.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(
          start: weekStart,
          end: weekStart.add(const Duration(days: 7)),
        );
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month + 1),
        );
      case 'custom':
        final range = _customRange;
        if (range == null) return null;
        final start =
            DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day)
            .add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  DateTime? _notificationDate(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  List<Map<String, dynamic>> _periodNotifications() {
    final range = _periodRange();
    if (_period == 'all') return widget.notifications;
    if (range == null) return const [];
    return widget.notifications.where((notification) {
      final date = _notificationDate(notification['createdAt']);
      return date != null &&
          !date.isBefore(range.start) &&
          date.isBefore(range.end);
    }).toList();
  }

  Future<void> _selectPeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            _customRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة الإشعارات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || range == null) return;
      setState(() {
        _period = period;
        _customRange = range;
      });
      return;
    }
    setState(() => _period = period);
  }

  @override
  Widget build(BuildContext context) {
    final periodNotifications = _periodNotifications();
    final visibleNotifications = _selectedCategory == null
        ? periodNotifications
        : periodNotifications
            .where((notification) =>
                notification['category']?.toString() == _selectedCategory)
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _period,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'فترة الإشعارات'),
                items: const [
                  DropdownMenuItem(value: 'day', child: Text('اليوم')),
                  DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                  DropdownMenuItem(value: 'month', child: Text('شهر')),
                  DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
                  DropdownMenuItem(value: 'all', child: Text('الكل')),
                ],
                onChanged: (period) {
                  if (period != null) _selectPeriod(period);
                },
              ),
              if (_period == 'custom' && _customRange != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${intl.DateFormat('y/MM/dd').format(_customRange!.start)}'
                    ' - ${intl.DateFormat('y/MM/dd').format(_customRange!.end)}',
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('الكل (${periodNotifications.length})'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                for (final entry in _categories.entries) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      '${entry.value} (${periodNotifications.where((notification) => notification['category']?.toString() == entry.key).length})',
                    ),
                    selected: _selectedCategory == entry.key,
                    onSelected: (_) => setState(() {
                      _selectedCategory =
                          _selectedCategory == entry.key ? null : entry.key;
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: visibleNotifications.isEmpty
              ? const Center(child: Text('لا توجد إشعارات ضمن الفترة المحددة'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: visibleNotifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = visibleNotifications[index];
                    final category = notification['category']?.toString();
                    final createdAt =
                        _notificationDate(notification['createdAt']);
                    final readAt = _notificationDate(notification['readAt']);
                    final data = notification['data'];
                    return ExpansionTile(
                      key: ValueKey(notification['id'] ?? index),
                      leading: Icon(
                        readAt == null
                            ? Icons.mark_email_unread_outlined
                            : Icons.notifications_none,
                      ),
                      title: Text(
                        notification['title']?.toString().trim().isNotEmpty ==
                                true
                            ? notification['title'].toString()
                            : 'إشعار',
                      ),
                      subtitle: Text(
                        notification['body']?.toString().trim().isNotEmpty ==
                                true
                            ? notification['body'].toString()
                            : '${_categories[category] ?? category ?? 'إشعار'}'
                                '${createdAt == null ? '' : ' · ${intl.DateFormat('y/MM/dd HH:mm').format(createdAt)}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      children: [
                        if (category != null)
                          ListTile(
                            title: const Text('نوع التنبيه'),
                            subtitle: Text(_categories[category] ?? category),
                          ),
                        if (notification['body'] != null)
                          ListTile(
                            title: const Text('التفاصيل'),
                            subtitle: Text(notification['body'].toString()),
                          ),
                        if (createdAt != null)
                          ListTile(
                            title: const Text('تاريخ الإرسال'),
                            subtitle: Text(
                              intl.DateFormat('y/MM/dd HH:mm')
                                  .format(createdAt),
                            ),
                          ),
                        ListTile(
                          title: const Text('حالة القراءة'),
                          subtitle:
                              Text(readAt == null ? 'غير مقروء' : 'مقروء'),
                        ),
                        if (data != null)
                          ListTile(
                            title: const Text('بيانات إضافية'),
                            subtitle: Text(data.toString()),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
