import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/case_message.dart';
import '../providers/case_message_provider.dart';
import 'case_message_detail_screen.dart';
import '../main.dart' show routeObserver;

class CaseMessageListScreen extends StatefulWidget {
  const CaseMessageListScreen({super.key});

  @override
  State<CaseMessageListScreen> createState() => _CaseMessageListScreenState();
}

class _CaseMessageListScreenState extends State<CaseMessageListScreen> with RouteAware {
  final ScrollController _scrollController = ScrollController();
  CaseMessageProvider? _provider; // 保存 provider 引用
  bool _isInitialized = false; // 標記是否已初始化

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 保存 provider 引用
    if (_provider == null) {
      _provider = Provider.of<CaseMessageProvider>(context, listen: false);
    }
    
    // 註冊 RouteAware，以便監聽頁面可見性變化
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    
    // 初始化並啟動自動刷新（只在第一次時）
    // 使用 postFrameCallback 延遲到 build 完成後執行，避免在 build 期間調用 notifyListeners
    if (!_isInitialized && _provider != null) {
      _isInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _provider!.fetchCaseMessageList(refresh: true);
          _provider!.startAutoRefresh();
        }
      });
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    
    // 使用保存的 provider 引用停止自動刷新
    _provider?.stopAutoRefresh();
    
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // 當從其他頁面返回到此頁面時調用
  @override
  void didPopNext() {
    debugPrint('CaseMessageListScreen: 返回此頁面，重新啟動 timer');
    _provider?.startAutoRefresh();
  }

  // 當從此頁面跳轉到其他頁面時調用
  @override
  void didPushNext() {
    debugPrint('CaseMessageListScreen: 離開此頁面，停止 timer');
    _provider?.stopAutoRefresh();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // 接近底部時加載更多
      final provider = Provider.of<CaseMessageProvider>(context, listen: false);
      if (!provider.isLoadingMore && provider.hasMore) {
        provider.loadMoreCases();
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
      case 'completed':
        return '已完成';
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
    final provider = Provider.of<CaseMessageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('案件訊息'),
        centerTitle: true,
        backgroundColor: const Color(0xFF469030),
        foregroundColor: Colors.white,
      ),
      body: provider.isLoading && provider.caseMessageList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.caseMessageList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.message_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '暫無案件訊息',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: provider.caseMessageList.length +
                      (provider.isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    // 加載更多指示器
                    if (index == provider.caseMessageList.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final item = provider.caseMessageList[index];
                    return _buildCaseMessageItem(context, item);
                  },
                ),
    );
  }

  Widget _buildCaseMessageItem(
      BuildContext context, CaseMessageListItem item) {
    return InkWell(
      onTap: () {
        // 導航到詳情頁（timer 由 RouteAware 自動管理）
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CaseMessageDetailScreen(
              caseId: item.id,
              caseNumber: item.caseNumber,
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
                      Icon(
                        Icons.person,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
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

