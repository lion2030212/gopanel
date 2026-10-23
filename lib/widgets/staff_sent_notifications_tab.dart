import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

class StaffSentNotificationsTab extends StatefulWidget {
  const StaffSentNotificationsTab({
    required this.client,
    required this.adminToken,
    required this.staffId,
    required this.onSessionExpired,
    super.key,
  });

  final Dio client;
  final String adminToken;
  final int staffId;
  final ValueChanged<String> onSessionExpired;

  @override
  State<StaffSentNotificationsTab> createState() =>
      _StaffSentNotificationsTabState();
}

class _StaffSentNotificationsTabState extends State<StaffSentNotificationsTab> {
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _campaigns = [];
  Map<String, dynamic> _roleCounts = const {};
  Map<String, dynamic> _categoryCounts = const {};
  String _role = 'all';
  String _period = 'week';
  String? _category;
  DateTimeRange? _customRange;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _requestId = 0;

  Options get _options => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNearEnd);
    unawaited(_loadPage());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNearEnd)
      ..dispose();
    super.dispose();
  }

  int _count(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  List<Map<String, dynamic>> _mapsFrom(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  String _errorFrom(DioException error) {
    final data = error.response?.data;
    return data is Map && data['message'] is String
        ? data['message'] as String
        : 'تعذر تحميل سجل التنبيهات المرسلة';
  }

  void _loadMoreWhenNearEnd() {
    if (_hasMore &&
        !_isLoading &&
        !_isLoadingMore &&
        _scrollController.position.extentAfter < 280) {
      unawaited(_loadPage(loadMore: true));
    }
  }

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
        return DateTimeRange(
          start: DateTime(range.start.year, range.start.month, range.start.day),
          end: DateTime(range.end.year, range.end.month, range.end.day)
              .add(const Duration(days: 1)),
        );
      default:
        return null;
    }
  }

  String _apiDate(DateTime value) =>
      intl.DateFormat('yyyy-MM-dd HH:mm:ss').format(value);

  Future<void> _selectPeriod(String period) async {
    DateTimeRange? customRange = _customRange;
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      customRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _customRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة التنبيهات',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted) return;
      if (customRange == null) {
        setState(() {});
        return;
      }
    }
    setState(() {
      _period = period;
      _customRange = customRange;
      _campaigns.clear();
      _roleCounts = const {};
      _categoryCounts = const {};
      _hasMore = false;
      _errorMessage = null;
    });
    unawaited(_loadPage());
  }

  void _selectCategory(String? category) {
    if (_category == category) return;
    setState(() {
      _category = category;
      _campaigns.clear();
      _hasMore = false;
      _errorMessage = null;
    });
    unawaited(_loadPage());
  }

  Future<void> _loadPage({bool loadMore = false}) async {
    if (loadMore && (_isLoadingMore || _isLoading || !_hasMore)) return;
    final requestId = ++_requestId;
    final beforeId = loadMore && _campaigns.isNotEmpty
        ? _campaigns.last['id']?.toString()
        : null;
    final range = _periodRange();
    final queryParameters = <String, dynamic>{
      'limit': 20,
      if (_role != 'all') 'role': _role,
      if (_category != null) 'category': _category,
      if (beforeId != null) 'beforeId': beforeId,
    };
    if (range != null) {
      queryParameters['startAt'] = _apiDate(range.start);
      queryParameters['endAt'] = _apiDate(range.end);
    }

    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _isLoadingMore = false;
        _errorMessage = null;
      }
    });

    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        '/api/admin/staff/${widget.staffId}/sent-notifications',
        queryParameters: queryParameters,
        options: _options,
      );
      final data = response.data ?? const {};
      if (!mounted || requestId != _requestId) return;
      setState(() {
        if (!loadMore) _campaigns.clear();
        _campaigns.addAll(_mapsFrom(data['items']));
        final counts = data['roleCounts'];
        _roleCounts = counts is Map ? Map<String, dynamic>.from(counts) : const {};
        final categoryCounts = data['categoryCounts'];
        _categoryCounts = categoryCounts is Map
            ? Map<String, dynamic>.from(categoryCounts)
            : const {};
        _hasMore = data['hasMore'] == true;
        _errorMessage = null;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired(_errorFrom(error));
      }
      setState(() {
        _errorMessage = _errorFrom(error);
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _errorMessage = 'تعذر تحميل سجل التنبيهات المرسلة';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refresh() => _loadPage();

  void _selectRole(String role) {
    if (_role == role) return;
    setState(() {
      _role = role;
      _campaigns.clear();
      _categoryCounts = const {};
      _hasMore = false;
      _errorMessage = null;
    });
    unawaited(_loadPage());
  }

  String _categoryLabel(String? category) {
    switch (category) {
      case 'promotion':
        return 'عرض ترويجي';
      case 'guidance':
        return 'توجيه';
      default:
        return 'خدمة العملاء';
    }
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'promotion':
        return Icons.local_offer_outlined;
      case 'guidance':
        return Icons.info_outline;
      default:
        return Icons.support_agent_outlined;
    }
  }

  String _formatDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '' : intl.DateFormat('y/MM/dd HH:mm').format(date);
  }

  String _selectedRangeLabel() {
    final range = _customRange;
    if (range == null) return '';
    return '${intl.DateFormat('y/MM/dd').format(range.start)}'
        ' - ${intl.DateFormat('y/MM/dd').format(range.end)}';
  }

  Widget _buildCampaign(Map<String, dynamic> campaign) {
    final category = campaign['category']?.toString();
    final date = _formatDate(campaign['createdAt']);
    final title = campaign['title']?.toString().trim();
    final body = campaign['body']?.toString().trim();
    return ExpansionTile(
      key: ValueKey(campaign['id']),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE8F2EB),
        child: Icon(_categoryIcon(category), color: const Color(0xFF398653)),
      ),
      title: Text(
        title?.isNotEmpty == true ? title! : 'تنبيه',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body?.isNotEmpty == true)
              Text(body!, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Text([_categoryLabel(category), date]
                .where((value) => value.isNotEmpty)
                .join(' · ')),
            const SizedBox(height: 5),
            Text(
              'سائقون ${_count(campaign['driverCount'])} · '
              'ركاب ${_count(campaign['riderCount'])} · '
              'مقروء ${_count(campaign['readCount'])}',
            ),
          ],
        ),
      ),
      children: [
        ListTile(
          title: const Text('حالة الإشعارات'),
          subtitle: Text(
            'مقبول عبر FCM: ${_count(campaign['acceptedCount'])} مستلم',
          ),
        ),
        ListTile(
          title: const Text('الأجهزة'),
          subtitle: Text(
            'تم قبول الإرسال إلى ${_count(campaign['acceptedDevices'])} جهاز · '
            'فشل ${_count(campaign['failedCount'])} · '
            'دون جهاز ${_count(campaign['noTokenCount'])}',
          ),
        ),
        ListTile(
          title: const Text('المقروءة'),
          subtitle: Text('${_count(campaign['readCount'])} إشعار'),
        ),
      ],
    );
  }

  Widget _buildCampaignList() {
    if (_campaigns.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_campaigns.isEmpty && _errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_campaigns.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Icon(Icons.notifications_none, size: 44, color: Colors.grey),
            SizedBox(height: 12),
            Center(child: Text('لا توجد تنبيهات مرسلة لهذا الموظف')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _campaigns.length + (_hasMore || _isLoadingMore || _errorMessage != null ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index < _campaigns.length) return _buildCampaign(_campaigns[index]);
          if (_errorMessage != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton.icon(
                onPressed: () => _loadPage(loadMore: true),
                icon: const Icon(Icons.refresh),
                label: const Text('تعذر تحميل المزيد · إعادة المحاولة'),
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(_period),
                  initialValue: _period,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'فترة التنبيهات'),
                  items: const [
                    DropdownMenuItem(value: 'day', child: Text('اليوم')),
                    DropdownMenuItem(value: 'week', child: Text('أسبوع')),
                    DropdownMenuItem(value: 'month', child: Text('شهر')),
                    DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                  ],
                  onChanged: (period) {
                    if (period != null) unawaited(_selectPeriod(period));
                  },
                ),
                if (_period == 'custom' && _customRange != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_selectedRangeLabel()),
                  ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minWidth: constraints.maxWidth),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      FilterChip(
                        label: Text('الكل (${_count(_categoryCounts['allCount'])})'),
                        selected: _category == null,
                        onSelected: (_) => _selectCategory(null),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(
                          'خدمة العملاء (${_count(_categoryCounts['customerServiceCount'])})',
                        ),
                        selected: _category == 'customer_service',
                        onSelected: (_) => _selectCategory(
                          _category == 'customer_service' ? null : 'customer_service',
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(
                          'عرض ترويجي (${_count(_categoryCounts['promotionCount'])})',
                        ),
                        selected: _category == 'promotion',
                        onSelected: (_) => _selectCategory(
                          _category == 'promotion' ? null : 'promotion',
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(
                          'توجيه (${_count(_categoryCounts['guidanceCount'])})',
                        ),
                        selected: _category == 'guidance',
                        onSelected: (_) => _selectCategory(
                          _category == 'guidance' ? null : 'guidance',
                        ),
                      ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minWidth: constraints.maxWidth),
                      child: Align(
                        alignment: Alignment.center,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: 'all',
                              label: Text(
                                  'الكل (${_count(_roleCounts['allCount'])})'),
                            ),
                            ButtonSegment(
                              value: 'driver',
                              label: Text(
                                  'السائق (${_count(_roleCounts['driverCount'])})'),
                            ),
                            ButtonSegment(
                              value: 'rider',
                              label: Text(
                                  'الراكب (${_count(_roleCounts['riderCount'])})'),
                            ),
                          ],
                          selected: {_role},
                          onSelectionChanged: (selection) =>
                              _selectRole(selection.first),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildCampaignList()),
        ],
      ),
    );
  }
}