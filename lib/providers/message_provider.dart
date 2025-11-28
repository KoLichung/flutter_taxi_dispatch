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
    // debugPrint('Fetching messages at ${DateTime.now()}, refresh=${refresh}');

    // Always use page 1 for automatic updates
    final int pageToFetch = 1;

    // If refresh is true, reset everything
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      // 不再清空訊息列表，保留臨時訊息
      _messageIds.clear();
    }

    // Only set loading flag when refreshing or emptying the list
    final bool shouldShowLoading = refresh || _messages.isEmpty;
    if (shouldShowLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // Always make the API call for page 1 to get newest messages
      // debugPrint('Making API request to fetch newest messages, page=${pageToFetch}');
      final response = await ApiConfig.getMessages(page: pageToFetch);
      
      final List<dynamic> results = response['results'];
      final serverMessages = results.map((e) => Message.fromJson(e)).toList();
      
      // 提取案件消息未讀數
      if (response.containsKey('case_message_unread_count')) {
        _caseMessageUnreadCount = response['case_message_unread_count'] ?? 0;
      }
      
      // 檢查是否有臨時訊息（id = -1）
      Message? tempMessage;
      if (_messages.isNotEmpty && _messages[0].id == -1) {
        tempMessage = _messages[0];
        
        // 檢查 server 是否已經有這個訊息
        final foundInServer = serverMessages.any(
          (msg) => msg.content == tempMessage!.content && 
                   msg.isFromServer == tempMessage.isFromServer
        );
        
        if (foundInServer) {
          debugPrint('臨時訊息已同步到 server，將被移除');
          tempMessage = null; // server 已經有了，不需要保留臨時訊息
        } else {
          debugPrint('臨時訊息尚未同步到 server，保留顯示');
        }
      }
      
      // 直接用 server 的訊息替換本地訊息（保持一致性）
      _messages = List.from(serverMessages);
      
      // 如果有臨時訊息且 server 還沒同步，加回到最前面
      if (tempMessage != null) {
        _messages.insert(0, tempMessage);
      }
      
      _updateMessageIds();
      _hasMore = response['next'] != null;
      
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
      // debugPrint('Loading older messages, page=${nextPage}');
      
      _isLoading = true;
      
      try {
        final response = await ApiConfig.getMessages(page: nextPage);
        
        final List<dynamic> results = response['results'];
        final olderMessages = results.map((e) => Message.fromJson(e)).toList();
        
        // debugPrint('Loaded ${olderMessages.length} older messages from page ${nextPage}');
        
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
          
          // Re-sort messages by creation time
          _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          _updateMessageIds();
          _hasMore = response['next'] != null;
          _currentPage = nextPage; // Only increment page counter here for pagination
          
          if (addedCount > 0) {
            notifyListeners();
            // debugPrint('Added $addedCount older messages, total now: ${_messages.length}');
          } else {
            // debugPrint('No new older messages found on page ${nextPage}');
          }
        } else {
          _hasMore = false;
          // debugPrint('No more older messages available');
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