import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

class SupportHistoryTab extends StatefulWidget {
  const SupportHistoryTab({
    required this.client,
    required this.adminToken,
    this.userId,
    this.userRole,
    this.adminId,
    required this.ticketsMode,
    required this.onSessionExpired,
    super.key,
  }) : assert(
          (userId != null && userRole != null && adminId == null) ||
              (userId == null && userRole == null && adminId != null),
        );

  final Dio client;
  final String adminToken;
  final int? userId;
  final String? userRole;
  final String? adminId;
  final bool ticketsMode;
  final ValueChanged<String> onSessionExpired;

  @override
  State<SupportHistoryTab> createState() => _SupportHistoryTabState();
}

class _SupportHistoryTabState extends State<SupportHistoryTab> {
  static const _pageSize = 50;

  String _period = 'all';
  String _partyRole = 'all';
  DateTimeRange? _customRange;
  List<Map<String, dynamic>> _items = [];
  int _page = 0;
  int _total = 0;
  int _requestId = 0;
  int _detailRequestId = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingDetail = false;
  String? _error;
  String? _detailError;
  String? _selectedRecordId;
  Map<String, dynamic>? _selectedRecord;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _messages = [];

  Options get _requestOptions => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  String get _historyPath => widget.ticketsMode
      ? '/api/admin/support/history/tickets'
      : '/api/admin/support/history/conversations';

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory(reset: true));
  }

  @override
  void didUpdateWidget(covariant SupportHistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.userRole != widget.userRole ||
        oldWidget.adminId != widget.adminId ||
        oldWidget.ticketsMode != widget.ticketsMode) {
      _items = [];
      _selectedRecordId = null;
      _selectedRecord = null;
      _detail = null;
      _messages = [];
      unawaited(_loadHistory(reset: true));
    }
  }

  DateTimeRange? _selectedRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'day':
        return DateTimeRange(
            start: today, end: today.add(const Duration(days: 1)));
      case 'week':
        final daysSinceSaturday = (now.weekday + 1) % 7;
        final start = today.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(
            start: start, end: start.add(const Duration(days: 7)));
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month + 1),
        );
      case 'custom':
        final selected = _customRange;
        if (selected == null) return null;
        final start = DateTime(
            selected.start.year, selected.start.month, selected.start.day);
        final end =
            DateTime(selected.end.year, selected.end.month, selected.end.day)
                .add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  String _formatDateTime(DateTime value) =>
      intl.DateFormat('yyyy-MM-dd HH:mm:ss').format(value);

  Future<void> _selectPeriod(String period) async {
    DateTimeRange? selectedRange = _customRange;
    if (period == 'custom') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      selectedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        initialDateRange:
            selectedRange ?? DateTimeRange(start: today, end: today),
        helpText: 'اختر مدة السجل',
        cancelText: 'إلغاء',
        confirmText: 'تطبيق',
        saveText: 'تطبيق',
      );
      if (!mounted || selectedRange == null) return;
    }
    setState(() {
      _period = period;
      if (period == 'custom') _customRange = selectedRange;
    });
    await _loadHistory(reset: true);
  }

  Future<void> _loadHistory({required bool reset}) async {
    final requestId = ++_requestId;
    final page = reset ? 1 : _page + 1;
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
      _error = null;
    });
    final query = <String, dynamic>{
      'page': page,
      'limit': _pageSize,
    };
    if (widget.adminId != null) {
      query['adminId'] = widget.adminId;
      query['userRole'] = _partyRole;
    } else {
      query['userId'] = widget.userId;
      query['userRole'] = widget.userRole;
    }
    final range = _selectedRange();
    if (range != null) {
      query['startAt'] = _formatDateTime(range.start);
      query['endAt'] = _formatDateTime(range.end);
    }
    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        _historyPath,
        queryParameters: query,
        options: _requestOptions,
      );
      if (!mounted || requestId != _requestId) return;
      final data = response.data ?? const {};
      final values = data[widget.ticketsMode ? 'tickets' : 'conversations'];
      final rows = values is List
          ? values
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      final total = (data['total'] as num?)?.toInt() ?? rows.length;
      setState(() {
        _items = reset ? rows : [..._items, ...rows];
        _page = page;
        _total = total;
        _loading = false;
        _loadingMore = false;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _requestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = widget.ticketsMode
            ? 'تعذر تحميل سجل الشكاوى'
            : 'تعذر تحميل سجل المحادثات';
      });
    }
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    final recordId = id.toString();
    if (_selectedRecordId == recordId) {
      _detailRequestId++;
      setState(() {
        _selectedRecordId = null;
        _selectedRecord = null;
        _detail = null;
        _messages = [];
        _detailError = null;
        _loadingDetail = false;
      });
      return;
    }
    final requestId = ++_detailRequestId;
    setState(() {
      _selectedRecordId = recordId;
      _selectedRecord = item;
      _detail = null;
      _messages = [];
      _detailError = null;
      _loadingDetail = true;
    });
    await _loadItemDetail(id, requestId);
  }

  Future<void> _loadItemDetail(int id, int requestId) async {
    final typePath = widget.ticketsMode ? 'tickets' : 'conversations';
    try {
      final response = await widget.client.get<Map<String, dynamic>>(
        '/api/admin/support/$typePath/$id',
        options: _requestOptions,
      );
      if (!mounted ||
          requestId != _detailRequestId ||
          _selectedRecordId != id.toString()) {
        return;
      }
      final data = response.data ?? const {};
      final record = data[widget.ticketsMode ? 'ticket' : 'conversation'];
      final messages = (data['messages'] as List? ?? [])
          .whereType<Map>()
          .map((message) => Map<String, dynamic>.from(message))
          .toList();
      if (!mounted || requestId != _detailRequestId) return;
      setState(() {
        _detail = record is Map ? Map<String, dynamic>.from(record) : null;
        _messages = messages;
        _loadingDetail = false;
      });
    } on DioException catch (error) {
      if (!mounted || requestId != _detailRequestId) return;
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
      } else {
        setState(() {
          _loadingDetail = false;
          _detailError = widget.ticketsMode
              ? 'تعذر فتح تفاصيل الشكوى'
              : 'تعذر فتح تفاصيل المحادثة';
        });
      }
    }
  }

  void _retryItemDetail() {
    final id = int.tryParse(_selectedRecordId ?? '');
    if (id == null || _selectedRecord == null) return;
    final requestId = ++_detailRequestId;
    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });
    unawaited(_loadItemDetail(id, requestId));
  }

  Widget _buildDetailPanel(String recordId) {
    return Directionality(
      key: ValueKey('support-history-detail-$recordId'),
      textDirection: TextDirection.rtl,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: _loadingDetail
              ? const Center(child: CircularProgressIndicator())
              : _detailError != null
                  ? Row(
                      children: [
                        Expanded(child: Text(_detailError!)),
                        TextButton(
                          onPressed: _retryItemDetail,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    )
                  : _buildDetailContents(recordId),
        ),
      ),
    );
  }

  Widget _buildDetailContents(String recordId) {
    final messages = _messages;
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              widget.ticketsMode
                  ? 'تفاصيل الشكوى #$recordId'
                  : 'محادثة خدمة العملاء',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'إغلاق التفاصيل',
            onPressed: () => unawaited(_openItem(_selectedRecord!)),
            icon: const Icon(Icons.expand_less),
          ),
        ],
      ),
      _buildParticipantDetails(_detail ?? _selectedRecord),
    ];
    final details = _detail?['details']?.toString().trim();
    if (widget.ticketsMode && details?.isNotEmpty == true) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(details!, textDirection: TextDirection.rtl),
          ),
        ),
      );
    }
    if (messages.isEmpty) {
      if (!widget.ticketsMode) {
        children.add(const Text('لا توجد رسائل في هذه المحادثة'));
      } else if (details?.isEmpty != false) {
        children.add(const Text('لا توجد رسائل إضافية'));
      }
    } else {
      for (final message in messages) {
        final isAdmin = message['senderType'] == 'admin';
        children.add(
          Align(
            alignment: isAdmin
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAdmin
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAdmin
                        ? 'خدمة العملاء'
                        : widget.userRole == 'driver'
                            ? 'السائق'
                            : 'الراكب',
                    style: Theme.of(context).textTheme.labelSmall,
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message['body']?.toString() ?? '',
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  String _recordDate(dynamic value) {
    final date = value is DateTime
        ? value.toLocal()
        : value is String
            ? DateTime.tryParse(value)?.toLocal()
            : null;
    return date == null ? '' : intl.DateFormat('y/MM/dd HH:mm').format(date);
  }

  String _personValue(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? 'غير متاح' : text;
  }

  String _roleLabel(dynamic value) {
    switch (value) {
      case 'driver':
        return 'سائق';
      case 'rider':
        return 'راكب';
      case 'employee':
        return 'موظف';
      default:
        return 'غير محدد';
    }
  }

  Widget _buildParticipantDetails(Map<String, dynamic>? record) {
    if (record == null) return const SizedBox.shrink();
    final lines = <String>[
      'صاحب السجل: ${_personValue(record['customerName'])} · '
          '${_personValue(record['customerPhone'])} · '
          '${_roleLabel(record['userRole'])}',
    ];
    if (record['supportEmployeeRole'] == 'employee') {
      lines.add(
        'موظف الدعم: ${_personValue(record['supportEmployeeName'])} · '
        '${_personValue(record['supportEmployeePhone'])} · موظف',
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: Theme.of(context).textTheme.bodySmall,
                textDirection: TextDirection.rtl,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecord(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final isExpanded = _selectedRecordId == id;
    final createdAt = _recordDate(item['createdAt']);
    final subtitle = widget.ticketsMode
        ? '${item['category'] ?? 'شكوى'} · ${item['status'] ?? ''} · $createdAt'
        : '${item['status'] == 'closed' ? 'مغلقة' : 'نشطة'} · $createdAt';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title:
                Text(widget.ticketsMode ? 'شكوى #$id' : 'محادثة خدمة العملاء'),
            isThreeLine: true,
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                _buildParticipantDetails(item),
              ],
            ),
            trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => unawaited(_openItem(item)),
          ),
          if (isExpanded) _buildDetailPanel(id),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _selectedRange();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: widget.adminId == null
              ? _buildPeriodFilter()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPartyFilter(),
                    const SizedBox(height: 8),
                    _buildPeriodFilter(),
                  ],
                ),
        ),
        if (_period == 'custom' && _customRange != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${intl.DateFormat('y/MM/dd').format(_customRange!.start)}'
              ' - ${intl.DateFormat('y/MM/dd').format(_customRange!.end)}',
            ),
          ),
        if (range != null) const Divider(height: 1),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: () =>
                                unawaited(_loadHistory(reset: true)),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Text(widget.ticketsMode
                              ? 'لا توجد شكاوى ضمن الفترة'
                              : 'لا توجد محادثات ضمن الفترة'),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadHistory(reset: true),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length +
                                (_items.length < _total ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              if (index == _items.length) {
                                return Center(
                                  child: TextButton(
                                    onPressed: _loadingMore
                                        ? null
                                        : () => unawaited(
                                            _loadHistory(reset: false)),
                                    child: Text(_loadingMore
                                        ? 'جارٍ التحميل...'
                                        : 'تحميل المزيد'),
                                  ),
                                );
                              }
                              return _buildRecord(_items[index]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildPartyFilter() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('صاحب السجل', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('الكل')),
              ButtonSegment(value: 'driver', label: Text('السائق')),
              ButtonSegment(value: 'rider', label: Text('الراكب')),
            ],
            selected: {_partyRole},
            onSelectionChanged: (selection) {
              setState(() => _partyRole = selection.first);
              unawaited(_loadHistory(reset: true));
            },
          ),
        ],
      );

  Widget _buildPeriodFilter() => InputDecorator(
        decoration: InputDecoration(
          labelText: widget.ticketsMode ? 'فترة الشكاوى' : 'فترة المحادثات',
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _period,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('الكل')),
              DropdownMenuItem(value: 'day', child: Text('يوم')),
              DropdownMenuItem(value: 'week', child: Text('أسبوع')),
              DropdownMenuItem(value: 'month', child: Text('شهر')),
              DropdownMenuItem(value: 'custom', child: Text('مدة محددة')),
            ],
            onChanged: (period) {
              if (period != null) unawaited(_selectPeriod(period));
            },
          ),
        ),
      );
}
