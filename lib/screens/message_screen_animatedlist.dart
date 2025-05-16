import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../models/message.dart';
import '../providers/message_provider.dart';
import '../providers/user_provider.dart';
import 'dart:async';
import '../utils/api_config.dart';
import '../utils/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MessageScreenAnimatedList extends StatefulWidget {
  const MessageScreenAnimatedList({super.key});

  @override
  _MessageScreenAnimatedListState createState() => _MessageScreenAnimatedListState();
}

class _MessageScreenAnimatedListState extends State<MessageScreenAnimatedList> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<Message> _displayedMessages = [];
  
  Timer? _timer;
  List<Message> _previousMessages = [];
  bool _isLoadingMore = false;
  bool _isKeyboardVisible = false;
  bool _showScrollButton = false;
  
  // Flag to track if the initial scroll to bottom has been done
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initMessages();
      _startAutoFetch();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initMessages() async {
    try {
      final messageProvider = Provider.of<MessageProvider>(context, listen: false);
      debugPrint("request loading");
      await messageProvider.init();
      
      if (mounted) {
        // 初始化消息列表到 AnimatedList
        for (var message in messageProvider.messages) {
          _displayedMessages.add(message);
        }
        
        // 初始化_previousMessages，以便後續比較
        _previousMessages = List.from(messageProvider.messages);
      }
      
      // Schedule scroll to bottom for initial load after messages are fetched
      if (mounted && !_initialScrollDone && messageProvider.messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
          _initialScrollDone = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入訊息: $e')),
        );
      }
    }
  }

  void _startAutoFetch() {
    // Auto fetch messages every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) return;
      
      try {
        final messageProvider = Provider.of<MessageProvider>(context, listen: false);
        debugPrint("request loading");
        await messageProvider.fetchMessages();
        
        // 檢查是否有新消息
        _updateDisplayedMessages();
      } catch (e) {
        debugPrint('Error in auto fetch: $e');
      }
    });
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    
    // For a reversed ListView, "bottom" (newest messages) is at position 0
    final double currentScroll = _scrollController.offset;
    final double delta = 50.0; // Consider "at bottom" if within 50 pixels
    
    return currentScroll <= delta;
  }

  bool _isAtTop() {
    if (!_scrollController.hasClients) return false;
    
    // For a reversed ListView, "top" (oldest messages) is at maxScrollExtent
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double currentScroll = _scrollController.offset;
    final double delta = 50.0; // Consider "at top" if within 50 pixels
    
    return (maxScroll - currentScroll) <= delta;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    
    debugPrint("auto scroll to bottom");
    _scrollController.animateTo(
      0, // Scroll to 0 instead of maxScrollExtent for a reversed ListView
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    
    // Hide the new message button when scrolled to bottom
    if (_showScrollButton) {
      setState(() {
        _showScrollButton = false;
      });
    }
  }

  void _onScroll() async {
    // Load more messages when user scrolls to the top (oldest messages)
    if (_isAtTop() && !_isLoadingMore) {
      final messageProvider = Provider.of<MessageProvider>(context, listen: false);
      if (messageProvider.hasMore) {
        debugPrint("loadMore: 開始加載更多消息");
        debugPrint("loadMore: 當前滾動位置: ${_scrollController.offset}");
        debugPrint("loadMore: 當前最大滾動範圍: ${_scrollController.position.maxScrollExtent}");
        
        setState(() {
          _isLoadingMore = true;
        });
        
        debugPrint("request loading");
        await messageProvider.loadMore();
        
        // 處理加載的舊消息
        _updateDisplayedMessagesForLoadMore();
        
        // 加載完成後記錄位置變化
        if (_scrollController.hasClients) {
          debugPrint("loadMore: 加載完成後滾動位置: ${_scrollController.offset}");
          debugPrint("loadMore: 加載完成後最大滾動範圍: ${_scrollController.position.maxScrollExtent}");
        }
        
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    }
    
    // Hide the new message button when user manually scrolls down to bottom
    if (_isAtBottom() && _showScrollButton) {
      setState(() {
        _showScrollButton = false;
      });
    }
    
    // Also hide button when user is actively scrolling to bottom
    if (_showScrollButton && _scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      setState(() {
        _showScrollButton = false;
      });
    }
  }

  // 更新顯示的消息列表，處理新消息的添加和動畫
  void _updateDisplayedMessages() {
    final messageProvider = Provider.of<MessageProvider>(context, listen: false);
    final currentMessages = messageProvider.messages;
    
    // 檢查是否有新消息
    bool hasActuallyNewMessages = false;
    List<Message> newMessages = [];
    
    if (_previousMessages.isNotEmpty && currentMessages.isNotEmpty) {
      // 從_previousMessages獲取最高ID
      final highestPreviousId = _previousMessages[0].id;
      
      // 檢查是否有消息ID高於現有的最高ID
      for (final message in currentMessages) {
        if (message.id > highestPreviousId && !_previousMessages.map((m) => m.id).contains(message.id)) {
          hasActuallyNewMessages = true;
          newMessages.add(message);
          debugPrint("新消息: 發現ID更高的消息: ${message.id} > $highestPreviousId");
        }
      }
    } else if (_previousMessages.isEmpty && currentMessages.isNotEmpty) {
      // 特殊情況：之前沒有消息，現在有了
      hasActuallyNewMessages = true;
      newMessages = List.from(currentMessages);
      debugPrint("新消息: 從空列表到有消息");
    }
    
    // 如果有新消息，更新顯示
    if (hasActuallyNewMessages) {
      final wasAtBottom = _isAtBottom();
      
      // 向 AnimatedList 添加新消息
      for (var message in newMessages) {
        // 檢查消息是否已存在
        if (!_displayedMessages.any((m) => m.id == message.id)) {
          // 在 _displayedMessages 的開頭插入新消息
          _displayedMessages.insert(0, message);
          
          // 通知 AnimatedList 插入新項目
          if (_listKey.currentState != null) {
            _listKey.currentState!.insertItem(0, duration: const Duration(milliseconds: 300));
          }
        }
      }
      
      debugPrint("got new message");
      
      // 如果用戶在底部，自動滾動到底部顯示新消息
      if (wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            debugPrint("新消息: 用戶在底部，準備滾動到底部");
            debugPrint("新消息: 滾動前位置: ${_scrollController.offset}");
            _scrollToBottom();
            debugPrint("新消息: 滾動後位置: ${_scrollController.offset}");
          }
        });
      } else {
        // 用戶不在底部，顯示新消息按鈕
        if (!_showScrollButton) {
          setState(() {
            _showScrollButton = true;
          });
        }
      }
    }
    
    // 更新 _previousMessages
    _previousMessages = List.from(currentMessages);
  }

  // 處理加載更多時的顯示更新
  void _updateDisplayedMessagesForLoadMore() {
    final messageProvider = Provider.of<MessageProvider>(context, listen: false);
    final currentMessages = messageProvider.messages;
    
    // 找到哪些消息是新加載的（在 currentMessages 中但不在 _displayedMessages 中）
    final newlyLoadedMessages = currentMessages.where(
      (message) => !_displayedMessages.any((m) => m.id == message.id)
    ).toList();
    
    // 按照創建時間排序，確保舊消息在列表末尾
    newlyLoadedMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // 將新加載的舊消息添加到 _displayedMessages 的末尾
    for (var message in newlyLoadedMessages) {
      _displayedMessages.add(message);
      
      // 通知 AnimatedList 插入新項目
      if (_listKey.currentState != null) {
        _listKey.currentState!.insertItem(
          _displayedMessages.length - 1,
          duration: const Duration(milliseconds: 300)
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    
    _messageController.clear();
    
    // Store current scroll position before sending
    final wasAtBottom = _isAtBottom();
    
    try {
      debugPrint("request loading");
      await Provider.of<MessageProvider>(context, listen: false).sendMessage(message);
      
      // Only scroll to bottom if we were already at the bottom before sending
      if (wasAtBottom) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發送訊息失敗: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final messageProvider = Provider.of<MessageProvider>(context);
    final username = userProvider.user?.name ?? userProvider.user?.phone ?? '用戶';
    
    _isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_isKeyboardVisible && _isAtBottom()) {
      Future.microtask(_scrollToBottom);
    }

    // 返回UI結構
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('24H 叫車 (動畫版) - $username'),
          centerTitle: true,
          backgroundColor: const Color(0xFF469030),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () async {
                await userProvider.logout();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: messageProvider.messages.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.7,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.message,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      '沒有訊息',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      '開始傳送訊息給系統',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      '提示: 輸入 "上車: 地址" 來派車',
                                      style: TextStyle(
                                        color: Color(0xFF469030),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : _buildAnimatedMessageList(),
                ),
                _buildMessageInput(),
              ],
            ),
            // New message button - show only when there are new messages and user is not at bottom
            if (_showScrollButton)
              Positioned(
                right: 16,
                bottom: _isKeyboardVisible ? 80 : 100,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(24),
                  color: const Color(0xFF469030),
                  child: InkWell(
                    onTap: _scrollToBottom,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.arrow_downward,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '新訊息',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedMessageList() {
    return AnimatedList(
      key: _listKey,
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: 16,
        bottom: 80,
        left: 16,
        right: 16,
      ),
      initialItemCount: _displayedMessages.length,
      itemBuilder: (context, index, animation) {
        return _buildAnimatedItem(context, index, animation);
      },
    );
  }

  // 構建帶有動畫效果的消息項
  Widget _buildAnimatedItem(BuildContext context, int index, Animation<double> animation) {
    final message = _displayedMessages[index];
    final isUserMessage = !message.isFromServer;

    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1.0, // 保持消息底部固定
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        )),
        child: FadeTransition(
          opacity: animation,
          child: Align(
            alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
            key: ValueKey<int>(message.id),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUserMessage ? const Color(0xFF469030) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 16,
                      color: isUserMessage ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isUserMessage ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 12, _isKeyboardVisible ? 8 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: '輸入訊息...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              maxLines: null,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            margin: const EdgeInsets.only(right: 4),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF469030),
              radius: 20,
              child: Transform.translate(
                offset: const Offset(1, 0), // Move 2 pixels to the right
                child: IconButton(
                  icon: const Icon(Icons.send),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  color: Colors.white,
                  onPressed: _sendMessage,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 