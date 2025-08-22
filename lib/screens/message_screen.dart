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
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'profile_screen.dart';
import 'search_message_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  List<Message> _previousMessages = [];
  bool _isLoadingMore = false;
  bool _isKeyboardVisible = false;
  bool _showScrollButton = false;
  
  // Flag to track if the initial scroll to bottom has been done
  bool _initialScrollDone = false;
  
  // 全域變數存儲 EditableTextState
  EditableTextState? _currentEditableTextState;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // 清除所有通知
    _clearNotifications();
    
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
      
      // 初始化_previousMessages，以便後續比較
      if (mounted) {
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
        // 簡化_startAutoFetch，只負責獲取數據，不處理UI或滾動位置
        final messageProvider = Provider.of<MessageProvider>(context, listen: false);
        debugPrint("request loading");
        await messageProvider.fetchMessages();
        // 數據變化會觸發build重建，滾動位置相關邏輯都放在build中處理
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
        // 使用SchedulerBinding確保在正確的時機執行滾動
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
      // 不再在這裡設置_showScrollButton，而是讓build方法處理
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發送訊息失敗: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime.add(const Duration(hours: 8)));
  }

  // 清除所有通知
  void _clearNotifications() async {
    try {
      // Firebase Messaging doesn't have clearAllNotifications method
      // We'll just log that we're clearing notifications
      debugPrint('已清除所有通知');
    } catch (e) {
      debugPrint('清除通知失敗: $e');
    }
  }

  // 自定義文字選擇選單
  Widget _buildContextMenu(BuildContext context, EditableTextState editableTextState) {
    final List<ContextMenuButtonItem> buttonItems = [];
    final TextEditingController controller = editableTextState.widget.controller!;
    final TextSelection selection = editableTextState.currentTextEditingValue.selection;

    // 只有在沒有選中文字時，才顯示"全選"和"選取"按鈕
    if (selection.isCollapsed) {
      // 全選
      if (controller.text.isNotEmpty) {
        buttonItems.add(
          ContextMenuButtonItem(
            label: '全選',
            onPressed: () {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
              // 不立即隱藏菜單，等待菜單自動更新
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // 延遲一點再重新顯示菜單，確保選中狀態已更新
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (editableTextState.mounted) {
                    editableTextState.showToolbar();
                  }
                });
              });
            },
          ),
        );
      }

      if (controller.text.isNotEmpty) {
        buttonItems.add(
          ContextMenuButtonItem(
            label: '選擇',
            onPressed: () {
              final cursorOffset = selection.baseOffset;
              final text = controller.text;
              
              // 找到當前游標位置所在行的開始位置
              int lineStart = cursorOffset;
              while (lineStart > 0 && text[lineStart - 1] != '\n') {
                lineStart--;
              }
              
              // 找到當前行的結束位置（下一個換行符或文字結尾）
              int lineEnd = cursorOffset;
              while (lineEnd < text.length && text[lineEnd] != '\n') {
                lineEnd++;
              }
              
              // 選擇整行
              controller.selection = TextSelection(
                baseOffset: lineStart,
                extentOffset: lineEnd,
              );
              // 不立即隱藏菜單，等待菜單自動更新
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // 延遲一點再重新顯示菜單，確保選中狀態已更新
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (editableTextState.mounted) {
                    editableTextState.showToolbar();
                  }
                });
              });
            },
          ),
        );
      }
    }

    // 複製 (當有選中文字時)
    if (!selection.isCollapsed && selection.textInside(controller.text).isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: '複製',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: selection.textInside(controller.text)));
            ContextMenuController.removeAny();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已複製到剪貼簿'),
                duration: Duration(milliseconds: 100),
              ),
            );
          },
        ),
      );
    }

    // 剪下 (當有選中文字時)
    if (!selection.isCollapsed && selection.textInside(controller.text).isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: '剪下',
          onPressed: () {
            final selectedText = selection.textInside(controller.text);
            Clipboard.setData(ClipboardData(text: selectedText));
            
            // 刪除選中的文字
            final newText = controller.text.replaceRange(
              selection.start,
              selection.end,
              '',
            );
            controller.text = newText;
            controller.selection = TextSelection.collapsed(offset: selection.start);
            
            ContextMenuController.removeAny();
            // ScaffoldMessenger.of(context).showSnackBar(
            //   const SnackBar(
            //     content: Text('已剪下到剪貼簿'),
            //     duration: Duration(milliseconds: 800),
            //   ),
            // );
          },
        ),
      );
    }

    // 貼上 (當剪貼簿有內容時)
    buttonItems.add(
      ContextMenuButtonItem(
        label: '貼上',
        onPressed: () async {
          final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
          if (clipboardData?.text != null) {
            final text = clipboardData!.text!;
            final newText = controller.text.replaceRange(
              selection.start,
              selection.end,
              text,
            );
            controller.text = newText;
            controller.selection = TextSelection.collapsed(
              offset: selection.start + text.length,
            );
            
            ContextMenuController.removeAny();
          }
        },
      ),
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final messageProvider = Provider.of<MessageProvider>(context);
    final username = userProvider.user?.nickName ?? userProvider.user?.phone ?? '用戶';
    
    // 只在非加載更多狀態下保存滾動位置（針對新消息到達的情況）
    final currentScrollPosition = !_isLoadingMore && _scrollController.hasClients 
        ? _scrollController.position.pixels 
        : 0.0;
    
    // 檢查消息列表是否變化
    final currentMessages = messageProvider.messages;
    final messagesChanged = !const ListEquality().equals(_previousMessages, currentMessages);
    
    // 標記是否需要恢復滾動位置（僅針對新消息情況）
    bool shouldRestorePosition = false;
    
    if (messagesChanged) {
      // 檢查是否有新消息（ID更高的消息）
      bool hasActuallyNewMessages = false;
      
      if (_previousMessages.isNotEmpty && currentMessages.isNotEmpty) {
        // 從_previousMessages獲取最高ID
        final highestPreviousId = _previousMessages[0].id;
        
        // 檢查是否有消息ID高於現有的最高ID
        for (final message in currentMessages) {
          if (message.id > highestPreviousId && !_previousMessages.map((m) => m.id).contains(message.id)) {
            hasActuallyNewMessages = true;
            debugPrint("新消息: 發現ID更高的消息: ${message.id} > $highestPreviousId");
            break;
          }
        }
      } else if (_previousMessages.isEmpty && currentMessages.isNotEmpty) {
        // 特殊情況：之前沒有消息，現在有了
        hasActuallyNewMessages = true;
        debugPrint("新消息: 從空列表到有消息");
      }
      
      // 在完成比較後更新_previousMessages
      _previousMessages = List.from(currentMessages);
      
      // 新消息到達且初始加載已完成且不是在加載更多舊消息
      if (hasActuallyNewMessages && _initialScrollDone && !_isLoadingMore) {
        // 用戶不在底部，顯示新消息按鈕並準備恢復滾動位置
        if (!_isAtBottom()) {
          debugPrint("got new message");
          debugPrint("新消息: 當前滾動位置: ${_scrollController.offset}");
          debugPrint("新消息: 當前最大滾動範圍: ${_scrollController.position.maxScrollExtent}");
          
          // 使用WidgetsBinding來更新按鈕狀態，避免在build中直接調用setState
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_showScrollButton) {
              setState(() {
                _showScrollButton = true;
              });
            }
          });
          
          // 只有新消息到達且用戶不在底部時才需要恢復滾動位置
          shouldRestorePosition = true;
        } else {
          // 用戶在底部，自動滾動到底部顯示新消息
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              debugPrint("新消息: 用戶在底部，準備滾動到底部");
              debugPrint("新消息: 滾動前位置: ${_scrollController.offset}");
              _scrollToBottom();
              debugPrint("新消息: 滾動後位置: ${_scrollController.offset}");
            }
          });
        }
      }
    }
    
    // 只為新消息到達的情況恢復滾動位置
    if (shouldRestorePosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients && !_isAtBottom()) {
          debugPrint("新消息: 恢復滾動位置前: ${_scrollController.offset}");
          // 調整：每新增一條消息，將滾動位置增加約32px
          // 這樣可以補償新消息加在前方導致的位移
          const newMessageHeightAdjustment = 72.0;
          _scrollController.jumpTo(currentScrollPosition + newMessageHeightAdjustment);
          debugPrint("新消息: 恢復滾動位置後: ${_scrollController.offset}, 調整了 ${newMessageHeightAdjustment}px");
        }
      });
    }

    // 鍵盤可見性處理（保留原有邏輯）
    _isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_isKeyboardVisible && _isAtBottom()) {
      Future.microtask(_scrollToBottom);
    }

    // 返回UI結構（保留原有邏輯）
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('24H 叫車 - ${userProvider.user?.nickName ?? '用戶'}'),
          centerTitle: true,  // Center the title
          backgroundColor: const Color(0xFF469030),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SearchMessageScreen()),
                );
              },
            ),
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
                                  children: [
                                    const Icon(
                                      Icons.message,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      '沒有訊息',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '開始傳送訊息給系統',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
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
                      : _MessageListView(
                          messages: messageProvider.messages,
                          scrollController: _scrollController,
                          formatTime: _formatTime,
                        ),
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
            child: GestureDetector(
              onDoubleTap: () {
                // 雙擊選擇當前行
                if (_messageController.text.isNotEmpty) {
                  final cursorOffset = _messageController.selection.baseOffset;
                  final text = _messageController.text;
                  
                  // 找到當前游標位置所在行的開始位置
                  int lineStart = cursorOffset;
                  while (lineStart > 0 && text[lineStart - 1] != '\n') {
                    lineStart--;
                  }
                  
                  // 找到當前行的結束位置（下一個換行符或文字結尾）
                  int lineEnd = cursorOffset;
                  while (lineEnd < text.length && text[lineEnd] != '\n') {
                    lineEnd++;
                  }
                  
                  // 選擇整行
                  _messageController.selection = TextSelection(
                    baseOffset: lineStart,
                    extentOffset: lineEnd,
                  );
                  
                  // 雙擊後顯示菜單
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (_currentEditableTextState != null && _currentEditableTextState!.mounted) {
                      _currentEditableTextState!.showToolbar();
                    }
                  });
                }
              },
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
                contextMenuBuilder: (context, editableTextState) {
                  _currentEditableTextState = editableTextState;
                  return _buildContextMenu(context, _currentEditableTextState!);
                },
              ),
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

// Optimized message list view component
class _MessageListView extends StatelessWidget {
  final List<Message> messages;
  final ScrollController scrollController;
  final String Function(DateTime) formatTime;
  
  const _MessageListView({
    required this.messages,
    required this.scrollController,
    required this.formatTime,
  });
  
  // 判斷是否為可取消的訊息類型
  bool _isCancellableMessage(String content) {
    try {
      final lines = content.split('\n');
      // 檢查是否至少有兩行
      if (lines.length < 2) return false;
      
      // 檢查第一行是否包含訂單號碼
      final firstLine = lines[0];
      if (!firstLine.contains('❤️')) return false;
      
      // 檢查第二行是否包含可取消的訊息特徵
      final secondLine = lines[1];
      return secondLine.contains('預約單成功') ||
             secondLine.contains('派單成功，正在尋找駕駛') ||
             secondLine.contains('車輛預估') ||
             secondLine.contains('司機到達地點');
    } catch (e) {
      print('Error in _isCancellableMessage: $e');
      return false;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      controller: scrollController,
      padding: const EdgeInsets.only(
        top: 16,
        bottom: 80,
        left: 16,
        right: 16,
      ),
      // Remove the key that was causing rebuild and auto-scroll
      itemCount: messages.length,
      itemBuilder: (context, index) {
        // Regular message
        final message = messages[index];
        return _buildMessageItem(context, message);
      },
    );
  }
  
  Widget _buildMessageItem(BuildContext context, Message message) {
    final isUserMessage = !message.isFromServer;
    final isCancellable = !isUserMessage && _isCancellableMessage(message.content);
    
    return Align(
      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      // Use key to help Flutter identify items properly
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: isCancellable ? 24 : 0),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 16,
                      color: isUserMessage ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (isCancellable)
                  Positioned(
                    left: -12,
                    top: 0,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          print("點擊取消按鈕");
                          // 顯示確認對話框
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              try {
                                // 獲取包含訂單編號的行
                                final lines = message.content.split('\n');
                                String? orderLine;
                                
                                for (final line in lines) {
                                  if (line.contains('❤️') && line.contains('❤️')) {
                                    orderLine = line;
                                    break;
                                  }
                                }
                                
                                final content = orderLine != null
                                    ? '取消\n$orderLine'
                                    : '確定要送出取消訊息嗎？';
                                
                                return AlertDialog(
                                  title: const Text('取消派單訊息', style: TextStyle(fontSize: 14)),
                                  content: Text(content, style: const TextStyle(fontSize: 16)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        print("確認送出取消訊息");
                                        
                                        // 發送取消訊息
                                        final messageProvider = Provider.of<MessageProvider>(context, listen: false);
                                        
                                        // 發送取消訊息的內容
                                        final messageContent = content;
                                        messageProvider.sendMessage(messageContent);
                                        
                                        // 滾動到底部
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          scrollController.animateTo(
                                            0,
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeOut,
                                          );
                                        });
                                      },
                                      child: const Text('送出'),
                                    ),
                                  ],
                                );
                              } catch (e) {
                                print('Error in dialog: $e');
                                return AlertDialog(
                                  title: const Text('錯誤'),
                                  content: Text('處理訊息時出錯: $e'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('確定'),
                                    ),
                                  ],
                                );
                              }
                            },
                          );
                        },
                        borderRadius: BorderRadius.circular(15),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isUserMessage ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                // 複製按鈕
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    // 顯示複製成功提示
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已複製訊息'),
                        duration: Duration(milliseconds: 300),
                      ),
                    );
                  },
                  child: Icon(
                    Icons.copy,
                    size: 24,
                    color: isUserMessage ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 