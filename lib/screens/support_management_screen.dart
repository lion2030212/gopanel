import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;

import '../core/admin_config.dart';

class SupportManagementScreen extends StatefulWidget {
  const SupportManagementScreen({
    required this.adminToken,
    required this.onSessionExpired,
    required this.ticketsMode,
    this.onTicketRead,
    this.client,
    super.key,
  });

  final String adminToken;
  final ValueChanged<String> onSessionExpired;
  final bool ticketsMode;
  final VoidCallback? onTicketRead;
  final Dio? client;

  @override
  SupportManagementScreenState createState() => SupportManagementScreenState();
}

class SupportManagementScreenState extends State<SupportManagementScreen> {
  static const _ticketStatuses = <String, String>{
    'open': 'مفتوحة',
    'in_progress': 'قيد المعالجة',
    'waiting_for_customer': 'بانتظار المستخدم',
    'resolved': 'مغلقة',
  };

  late final Dio _dio;
  final TextEditingController _replyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  Timer? _searchTimer;
  socket_io_client.Socket? _socket;
  Map<String, dynamic>? _selectedItem;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _messages = [];
  String _statusFilter = 'active';
  String? _error;
  bool _loadingList = true;
  bool _loadingDetail = false;
  bool _sending = false;
  bool _updatingStatus = false;

  Options get _auth => Options(
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );

  int? _id(dynamic value) => int.tryParse(value?.toString() ?? '');

  void showList() {
    if (!mounted) return;
    setState(() {
      _selectedItem = null;
      _detail = null;
      _messages = [];
      _loadingDetail = false;
      _replyController.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _dio = widget.client ?? Dio(BaseOptions(baseUrl: adminApiBaseUrl));
    unawaited(_loadItems());
    _connectSocket();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _socket?.dispose();
    _replyController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _collectionPath => widget.ticketsMode
      ? '/api/admin/support/tickets'
      : '/api/admin/support/conversations';

  String get _detailPath => widget.ticketsMode ? 'tickets' : 'conversations';

  Future<void> _loadItems() async {
    try {
      final query = <String, dynamic>{'limit': 100};
      if (widget.ticketsMode) {
        query['status'] = _statusFilter;
        if (_searchController.text.trim().isNotEmpty) {
          query['search'] = _searchController.text.trim();
        }
      }
      final response = await _dio.get<Map<String, dynamic>>(
        _collectionPath,
        queryParameters: query,
        options: _auth,
      );
      final data = response.data ?? const {};
      final rows =
          (data[widget.ticketsMode ? 'tickets' : 'conversations'] as List? ??
                  [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _loadingList = false;
        _error = null;
        if (_selectedItem != null) {
          final selectedId = _id(_selectedItem!['id']);
          _selectedItem =
              rows.where((item) => _id(item['id']) == selectedId).firstOrNull ??
                  _selectedItem;
        }
      });
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
        return;
      }
      if (mounted) {
        setState(() {
          _loadingList = false;
          _error =
              'تعذر تحميل ${widget.ticketsMode ? 'تذاكر' : 'محادثات'} الدعم';
        });
      }
    }
  }

  void _connectSocket() {
    final socket = socket_io_client.io(
      '$adminApiBaseUrl/admin',
      socket_io_client.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': widget.adminToken})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) {
      final id = _id(_selectedItem?['id']);
      if (id == null) return;
      socket.emit(
        widget.ticketsMode
            ? 'support:ticket:join'
            : 'support:conversation:join',
        {widget.ticketsMode ? 'ticketId' : 'conversationId': id},
      );
    });
    socket.on('support:conversation:message', (_) {
      if (!widget.ticketsMode) unawaited(_refreshSelectedAndList());
    });
    socket.on('support:conversations:changed', (_) {
      if (!widget.ticketsMode) unawaited(_refreshSelectedAndList());
    });
    socket.on('support:tickets:changed', (_) {
      if (widget.ticketsMode) unawaited(_refreshSelectedAndList());
    });
    socket.connect();
  }

  Future<void> _refreshSelectedAndList() async {
    await _loadItems();
    final id = _id(_selectedItem?['id']);
    if (id != null) await _loadDetail(id);
  }

  Future<void> _selectItem(Map<String, dynamic> item) async {
    final id = _id(item['id']);
    if (id == null) return;
    _socket?.emit(
      widget.ticketsMode ? 'support:ticket:join' : 'support:conversation:join',
      {widget.ticketsMode ? 'ticketId' : 'conversationId': id},
    );
    setState(() {
      _selectedItem = item;
      _loadingDetail = true;
    });
    await _loadDetail(id);
  }

  Future<void> _loadDetail(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/admin/support/$_detailPath/$id',
        options: _auth,
      );
      final data = response.data ?? const {};
      final messages = (data['messages'] as List? ?? [])
          .whereType<Map>()
          .map((message) => Map<String, dynamic>.from(message))
          .toList();
      if (!mounted) return;
      setState(() {
        final detail = data[widget.ticketsMode ? 'ticket' : 'conversation'];
        _detail = detail is Map ? Map<String, dynamic>.from(detail) : null;
        _messages = messages;
        _loadingDetail = false;
      });
      if (widget.ticketsMode) widget.onTicketRead?.call();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        widget.onSessionExpired('جلسة الإدارة غير صالحة');
      } else if (mounted) {
        setState(() => _loadingDetail = false);
      }
    }
  }

  Future<void> _sendReply() async {
    final id = _id(_selectedItem?['id']);
    final body = _replyController.text.trim();
    if (id == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _dio.post(
        '/api/admin/support/$_detailPath/$id/messages',
        data: {'message': body},
        options: _auth,
      );
      _replyController.clear();
      await _loadDetail(id);
      await _loadItems();
    } on DioException catch (error) {
      if (mounted) {
        final message = error.response?.data is Map
            ? error.response?.data['message']?.toString()
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message ?? 'تعذر إرسال الرد')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    final id = _id(_selectedItem?['id']);
    if (id == null || _updatingStatus) return;
    setState(() => _updatingStatus = true);
    try {
      await _dio.patch(
        '/api/admin/support/tickets/$id/status',
        data: {'status': status},
        options: _auth,
      );
      await _loadDetail(id);
      await _loadItems();
    } on DioException catch (error) {
      if (mounted) {
        final message = error.response?.data is Map
            ? error.response?.data['message']?.toString()
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message ?? 'تعذر تحديث حالة التذكرة')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _closeConversation() async {
    final id = _id(_selectedItem?['id']);
    if (id == null) return;
    try {
      await _dio.patch(
        '/api/admin/support/conversations/$id/status',
        data: const {'status': 'closed'},
        options: _auth,
      );
      if (!mounted) return;
      setState(() {
        _selectedItem = null;
        _detail = null;
        _messages = [];
      });
      await _loadItems();
    } on DioException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إغلاق المحادثة')),
        );
      }
    }
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), _loadItems);
  }

  String _roleLabel(String? role) => role == 'driver' ? 'سائق' : 'راكب';

  String _ticketStatus(String? value) => _ticketStatuses[value] ?? 'غير معروفة';

  @override
  Widget build(BuildContext context) {
    final title = widget.ticketsMode ? 'إدارة الشكاوى' : 'إدارة المحادثات';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return _selectedItem == null
                  ? _buildListPanel(title)
                  : _buildDetailPanel(showBack: true);
            }
            return Row(
              children: [
                SizedBox(width: 340, child: _buildListPanel(title)),
                const VerticalDivider(width: 1),
                Expanded(child: _buildDetailPanel()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildListPanel(String title) => Column(
        children: [
          if (widget.ticketsMode) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث برقم التذكرة أو العميل',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'مسح البحث',
                    onPressed: () {
                      _searchController.clear();
                      _loadItems();
                    },
                    icon: const Icon(Icons.close),
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: _searchChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonFormField<String>(
                initialValue: _statusFilter,
                decoration: const InputDecoration(labelText: 'حالة التذاكر'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('النشطة')),
                  DropdownMenuItem(value: 'all', child: Text('الكل')),
                  DropdownMenuItem(value: 'open', child: Text('مفتوحة')),
                  DropdownMenuItem(
                      value: 'in_progress', child: Text('قيد المعالجة')),
                  DropdownMenuItem(
                      value: 'waiting_for_customer',
                      child: Text('بانتظار المستخدم')),
                  DropdownMenuItem(value: 'resolved', child: Text('مغلقة')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _statusFilter = value);
                  unawaited(_loadItems());
                },
              ),
            ),
          ],
          Expanded(
            child: _loadingList
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!),
                          TextButton(
                              onPressed: _loadItems,
                              child: const Text('إعادة المحاولة')),
                        ]),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Text(widget.ticketsMode
                                ? 'لا توجد تذاكر'
                                : 'لا توجد محادثات نشطة'))
                        : RefreshIndicator(
                            onRefresh: _loadItems,
                            child: ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) =>
                                  _buildListTile(_items[index]),
                            ),
                          ),
          ),
        ],
      );

  Widget _buildListTile(Map<String, dynamic> item) {
    final id = _id(item['id']) ?? 0;
    final isSelected = _id(_selectedItem?['id']) == id;
    final isDriverOrigin = item['userRole']?.toString() == 'driver';
    final role = _roleLabel(item['userRole']?.toString());
    final title = widget.ticketsMode
        ? 'تذكرة #$id'
        : (item['customerName']?.toString().trim().isNotEmpty == true
            ? item['customerName'].toString()
            : '$role #${item['userId']}');
    final subtitle = widget.ticketsMode
        ? '${_categoryLabel(item['category']?.toString())} · ${_ticketStatus(item['status']?.toString())}'
        : '$role · ${item['customerPhone'] ?? ''}';
    final unread = _id(item['unreadCount']) ?? 0;
    return ListTile(
      selected: isSelected,
      tileColor: isDriverOrigin ? Colors.yellow.shade100 : null,
      selectedTileColor: isDriverOrigin ? Colors.yellow.shade200 : null,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: widget.ticketsMode
          ? item['rideId'] == null
              ? null
              : Text('رحلة #${item['rideId']}')
          : unread == 0
              ? null
              : CircleAvatar(
                  radius: 13,
                  backgroundColor: Theme.of(context).colorScheme.error,
                  child: Text('$unread',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
      onTap: () => _selectItem(item),
    );
  }

  Widget _buildDetailPanel({bool showBack = false}) {
    if (_selectedItem == null) {
      return const Center(child: Text('اختر محادثة أو تذكرة لعرض التفاصيل'));
    }
    final detail = _detail;
    final id = _id(_selectedItem!['id']) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  tooltip: 'العودة إلى القائمة',
                  onPressed: () => setState(() => _selectedItem = null),
                  icon: const Icon(Icons.arrow_forward),
                ),
              Expanded(
                child: Text(
                  widget.ticketsMode
                      ? 'تذكرة #$id'
                      : detail?['customerName']?.toString() ?? 'محادثة الدعم',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!widget.ticketsMode && detail != null)
                Text(
                    '${_roleLabel(detail['userRole']?.toString())} · ${detail['customerPhone'] ?? ''}'),
              if (!widget.ticketsMode && detail != null)
                IconButton(
                  tooltip: 'إنهاء المحادثة',
                  onPressed: _closeConversation,
                  icon: const Icon(Icons.check_circle_outline),
                ),
            ],
          ),
        ),
        if (widget.ticketsMode && detail != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '${detail['customerName'] ?? 'عميل'} · ${_roleLabel(detail['userRole']?.toString())} · ${detail['customerPhone'] ?? ''}',
            ),
          ),
          _buildRideContext(detail),
        ],
        if (widget.ticketsMode && detail != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Text('الحالة:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: detail['status']?.toString() ?? 'open',
                    decoration: const InputDecoration(isDense: true),
                    items: _ticketStatuses.entries
                        .map((entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ))
                        .toList(),
                    onChanged: _updatingStatus
                        ? null
                        : (value) {
                            if (value != null) unawaited(_changeStatus(value));
                          },
                  ),
                ),
                if (_updatingStatus)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 8),
                    child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        if (_loadingDetail)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.ticketsMode && detail != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _messageBubble(
                        detail['details']?.toString() ?? '', false),
                  ),
                ..._messages.map((message) {
                  final isAdmin = message['senderType'] == 'admin';
                  return Align(
                    alignment:
                        isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                    child: _messageBubble(
                        message['body']?.toString() ?? '', isAdmin),
                  );
                }),
              ],
            ),
          ),
        if (!widget.ticketsMode || detail?['status'] != 'resolved')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    maxLength: widget.ticketsMode ? 5000 : 1000,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'اكتب الرد',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'إرسال الرد',
                  onPressed: _sending ? null : _sendReply,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRideContext(Map<String, dynamic> detail) {
    final rideId = detail['rideId'];
    if (rideId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('لا توجد رحلة مرتبطة بهذه التذكرة'),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('الرحلة #$rideId · ${detail['rideStatus'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (detail['pickupAddress'] != null)
          Text('من: ${detail['pickupAddress']}'),
        if (detail['dropoffAddress'] != null)
          Text('إلى: ${detail['dropoffAddress']}'),
      ]),
    );
  }

  Widget _messageBubble(String body, bool isAdmin) => Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isAdmin ? const Color(0xFFE7F1E9) : const Color(0xFFEAF2FA),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(body),
      );

  String _categoryLabel(String? value) => switch (value) {
        'payment' => 'مشكلة في الدفع',
        'driver_issue' => 'مشكلة مع السائق',
        'past_ride' => 'رحلة سابقة',
        'technical' => 'مشكلة تقنية',
        _ => 'أخرى',
      };
}
