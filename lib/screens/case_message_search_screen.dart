import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/case_message.dart';
import '../utils/api_service.dart';
import 'case_message_detail_screen.dart';

class CaseMessageSearchScreen extends StatefulWidget {
  const CaseMessageSearchScreen({super.key});

  @override
  State<CaseMessageSearchScreen> createState() =>
      _CaseMessageSearchScreenState();
}

class _CaseMessageSearchScreenState extends State<CaseMessageSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<CaseMessageListItem> _results = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentPage = 1;
  String _lastQuery = '';
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _search({bool fromButton = false}) async {
    final query = _searchController.text.trim();
    if (_isLoading) return;

    _focusNode.unfocus();
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _results = [];
      _currentPage = 1;
      _hasMore = false;
      _lastQuery = query;
    });

    try {
      final response =
          await ApiService.searchCases(query: query, page: 1);
      final List<dynamic> results = response['results'] ?? [];
      setState(() {
        _results = results.map((e) => CaseMessageListItem.fromJson(e)).toList();
        _hasMore = response['next'] != null;
        _currentPage = 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final response =
          await ApiService.searchCases(query: _lastQuery, page: nextPage);
      final List<dynamic> results = response['results'] ?? [];
      final moreItems =
          results.map((e) => CaseMessageListItem.fromJson(e)).toList();

      setState(() {
        _results.addAll(moreItems);
        _currentPage = nextPage;
        _hasMore = response['next'] != null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加載更多失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '剛创';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} 分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} 小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} 天前';
    } else {
      return DateFormat('MM/dd HH:mm').format(dateTime);
    }
  }

  String _getCaseStateText(String state) {
    switch (state) {
      case 'way_to_catch':
        return '前往接客';
      case 'on_road':
        return '行程中';
      case 'catched':
        return '任務中';
      case 'arrived':
        return '已到達';
      case 'finished':
        return '完成任務';
      case 'canceled':
        return '已取消';
      default:
        return state;
    }
  }

  Color _getCaseStateColor(String state) {
    switch (state) {
      case 'way_to_catch':
        return Colors.orange;
      case 'on_road':
        return Colors.blue;
      case 'arrived':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索案件'),
        backgroundColor: const Color(0xFF469030),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索欄（固定在頂部）
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(fromButton: true),
                    decoration: InputDecoration(
                      hintText: '輸入地址關鍵字搜索（近七天）',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _search(fromButton: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF469030),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 結果區域
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '輸入地址關鍵字進行搜索',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '找不到符合的案件',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _results.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildCaseMessageItem(context, _results[index]);
      },
    );
  }

  Widget _buildCaseMessageItem(
      BuildContext context, CaseMessageListItem item) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CaseMessageDetailScreen(
              caseId: item.id,
              caseNumber: item.caseNumber,
              pickupAddress: item.onAddress,
              driverId: item.driverId,
              dispatcherId: item.dispatcherId,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側：案件資訊和最新消息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 案件編號和狀態
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.caseNumber,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getCaseStateColor(item.caseState)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getCaseStateText(item.caseState),
                          style: TextStyle(
                            fontSize: 11,
                            color: _getCaseStateColor(item.caseState),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // 司機資訊
                  Row(
                    children: [
                      Icon(Icons.person,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '${item.driverNickName}（${item.driverName}）',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // 地址（搜索結果突出顯示地址）
                  if (item.onAddress != null && item.onAddress!.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.onAddress!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],

                  // 最新消息
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.latestMessage != null
                              ? (item.latestMessage!.messageType == 'image'
                                  ? '[圖片] ${item.latestMessage!.content}'
                                  : item.latestMessage!.content)
                              : '暫無訊息',
                          style: TextStyle(
                            fontSize: 14,
                            color: item.latestMessage == null
                                ? Colors.grey.shade400
                                : (item.unreadCount > 0
                                    ? Colors.black87
                                    : Colors.grey.shade600),
                            fontWeight: item.unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                            fontStyle: item.latestMessage == null
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 右側：時間和未讀數
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.latestMessage != null
                      ? _formatTime(item.latestMessage!.createdAt)
                      : _formatTime(item.createTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                if (item.unreadCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        item.unreadCount > 99 ? '99+' : '${item.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
