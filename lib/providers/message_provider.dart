import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/message.dart';
import '../utils/api_config.dart';
import '../utils/push_notification_service.dart';

class MessageProvider extends ChangeNotifier {
  List<Message> _messages = [];
  bool _isLoading = false;
  int _currentPage = 1;
  bool _hasMore = true;
  Set<int> _messageIds = {};
  int _caseMessageUnreadCount = 0; // 案件消息未讀數

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  int get caseMessageUnreadCount => _caseMessageUnreadCount; // 案件消息未讀數的 getter

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await fetchMessages(refresh: true);
    } catch (e) {
      debugPrint('Error initializing messages: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Track message IDs to detect changes
  void _updateMessageIds() {
    _messageIds = _messages.map((msg) => msg.id).toSet();
  }

  // For automatic 3-second updates - always fetches page 1 for newest messages
  Future<void> fetchMessages({bool refresh = false}) async {
    // Always log the fetch attempt
    debugPrint('fetchMessages: 被調用 (refresh=$refresh), 當前消息數: ${_messages.length}, currentPage: $_currentPage');

    // Always use page 1 for automatic updates
    final int pageToFetch = 1;

    // If refresh is true, reset everything
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      // 不再清空訊息列表，保留臨時訊息
      _messageIds.clear();
      debugPrint('fetchMessages: refresh=true，重置 currentPage 和 hasMore');
    }

    // Only set loading flag when refreshing or emptying the list
    final bool shouldShowLoading = refresh || _messages.isEmpty;
    if (shouldShowLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // Always make the API call for page 1 to get newest messages
      debugPrint('fetchMessages: 請求第 $pageToFetch 頁獲取最新消息');
      final response = await ApiConfig.getMessages(page: pageToFetch);
      
      final List<dynamic> results = response['results'];
      final serverMessages = results.map((e) => Message.fromJson(e)).toList();
      
      debugPrint('fetchMessages: 從 API 獲取到 ${serverMessages.length} 條消息');
      
      // 提取案件消息未讀數
      if (response.containsKey('case_message_unread_count')) {
        _caseMessageUnreadCount = response['case_message_unread_count'] ?? 0;
      }
      
      // 統計並移除所有臨時訊息（fetch 成功後，完全以 server 數據為準）
      final tempMessagesCount = _messages.where((msg) => msg.id < 0).length;
      if (tempMessagesCount > 0) {
        debugPrint('fetchMessages: 檢測到 $tempMessagesCount 條臨時訊息，將全部移除（以 server 數據為準）');
      }
      
      // 如果 currentPage > 1，說明用戶已經加載了更多舊消息
      // 我們應該只更新第 1 頁的消息，保留其他頁的消息（但排除臨時訊息）
      if (_currentPage > 1) {
        debugPrint('fetchMessages: 檢測到已加載多頁消息 (currentPage=$_currentPage)，合併消息列表');
        
        // 先移除所有臨時訊息
        _messages.removeWhere((msg) => msg.id < 0);
        
        // 創建一個 Map 來快速查找已有消息
        final existingMessagesMap = {for (var msg in _messages) msg.id: msg};
        
        // 用新的第 1 頁消息更新或添加
        int updatedCount = 0;
        int addedCount = 0;
        
        for (final serverMsg in serverMessages) {
          if (existingMessagesMap.containsKey(serverMsg.id)) {
            // 更新已有消息
            final index = _messages.indexWhere((m) => m.id == serverMsg.id);
            if (index != -1) {
              _messages[index] = serverMsg;
              updatedCount++;
            }
          } else {
            // 添加新消息
            _messages.add(serverMsg);
            addedCount++;
          }
        }
        
        debugPrint('fetchMessages: 更新了 $updatedCount 條消息，添加了 $addedCount 條新消息');
        
        // 重新排序
        _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } else {
        // currentPage = 1，這是初始加載或刷新，直接替換（移除所有臨時訊息）
        debugPrint('fetchMessages: currentPage=1，直接替換消息列表（移除所有臨時訊息）');
        _messages = List.from(serverMessages);
      }
      
      _updateMessageIds();
      _hasMore = response['next'] != null;
      
      debugPrint('fetchMessages: 完成，總消息數: ${_messages.length}, hasMore: $_hasMore');
      
      // Notify listeners about the changes
      notifyListeners();
      
    } catch (e) {
      debugPrint('Error fetching messages: $e');
      if (shouldShowLoading) {
        rethrow; // Only re-throw if we showed loading
      }
    } finally {
      // Only update loading state if we were showing loading
      if (shouldShowLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // This method is specifically for pagination when scrolling up to see older messages
  Future<void> loadMore() async {
    if (!_isLoading && _hasMore) {
      final nextPage = _currentPage + 1;
      debugPrint('loadMore: 開始加載第 ${nextPage} 頁，當前消息數: ${_messages.length}');
      
      _isLoading = true;
      
      try {
        final response = await ApiConfig.getMessages(page: nextPage);
        
        final List<dynamic> results = response['results'];
        final olderMessages = results.map((e) => Message.fromJson(e)).toList();
        
        debugPrint('loadMore: 從第 ${nextPage} 頁獲取到 ${olderMessages.length} 條消息');
        debugPrint('loadMore: 當前消息列表中的消息 ID: ${_messages.map((m) => m.id).take(5).join(", ")}...');
        
        if (olderMessages.isNotEmpty) {
          // Only add messages we don't already have
          final messagesMap = {for (var msg in _messages) msg.id: msg};
          int addedCount = 0;
          
          for (final message in olderMessages) {
            if (!messagesMap.containsKey(message.id)) {
              _messages.add(message);
              addedCount++;
            }
          }
          
          debugPrint('loadMore: 新增了 $addedCount 條消息 (去重後)');
          
          // Re-sort messages by creation time
          _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          _updateMessageIds();
          _hasMore = response['next'] != null;
          _currentPage = nextPage; // Only increment page counter here for pagination
          
          debugPrint('loadMore: 加載完成，總消息數: ${_messages.length}, hasMore: $_hasMore');
          
          if (addedCount > 0) {
            notifyListeners();
            debugPrint('loadMore: 已通知 UI 更新');
          } else {
            debugPrint('loadMore: 沒有新消息，不更新 UI');
          }
        } else {
          _hasMore = false;
          debugPrint('loadMore: 沒有更多舊消息');
        }
      } catch (e) {
        debugPrint('Error loading more messages: $e');
        // If we get a 404, it means we've reached the end of available pages
        if (e.toString().contains('404')) {
          _hasMore = false;
          debugPrint('Reached end of messages (404 response)');
        }
      } finally {
        _isLoading = false;
      }
    } else {
      debugPrint('loadMore: 跳過加載 (isLoading: $_isLoading, hasMore: $_hasMore)');
    }
  }

  Future<void> sendMessage(String content, {bool isFromServer = false}) async {
    try {
      debugPrint('發送訊息: $content');
      
      // Create a temporary message immediately
      final tempMessage = Message(
        id: -1,  // Use -1 as a temporary ID
        content: content,
        isFromServer: isFromServer,
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      );
      
      // Add the temporary message to the list immediately
      _messages.insert(0, tempMessage);
      notifyListeners();
      
      // Send the message to the server
      final response = await ApiConfig.sendMessage(content, isFromServer: isFromServer);
      
      debugPrint('訊息發送成功: ${response['message']}');
      
      // 不主動調用 fetchMessages，等待定時刷新自動同步
      // 這樣可以避免因延遲導致訊息重複或消失的問題
      
    } catch (e) {
      debugPrint('Error sending message: $e');
      
      // Remove the temporary message if sending failed
      if (_messages.isNotEmpty && _messages[0].id == -1) {
        _messages.removeAt(0);
        notifyListeners();
      }
      
      rethrow;
    }
  }



  // 處理收到的推播通知
  void handleReceivedPushNotification(Map<String, dynamic> data) {
    final type = data['type'] ?? 'general';
    
    switch (type) {
      case 'new_message':
        debugPrint('收到新訊息推播，重新載入訊息');
        fetchMessages(refresh: true);
        break;
      case 'system_notification':
        debugPrint('收到系統通知推播');
        // 可以在這裡處理系統通知的特殊邏輯
        break;
      default:
        debugPrint('收到一般推播通知: $data');
        // 預設行為：重新載入訊息
        fetchMessages(refresh: false);
        break;
    }
  }
} 