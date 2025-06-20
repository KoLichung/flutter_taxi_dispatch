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

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

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

  // Check if a list of messages contains new ones
  bool _hasNewMessages(List<Message> newMessages) {
    // If we have no existing messages, definitely has changes
    if (_messages.isEmpty || _messageIds.isEmpty) {
      debugPrint('No existing messages, so has changes');
      return true;
    }
    
    final newIds = newMessages.map((msg) => msg.id).toSet();
    
    // Find IDs that are in newIds but not in _messageIds
    final newlyAdded = newIds.difference(_messageIds);
    
    // If there are any new IDs, we have changes
    final hasChanges = newlyAdded.isNotEmpty;
    
    if (hasChanges) {
      debugPrint('Found ${newlyAdded.length} new message IDs: $newlyAdded');
    }
    
    return hasChanges;
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
      final newMessages = results.map((e) => Message.fromJson(e)).toList();
      
      // 檢查是否有臨時訊息需要更新
      if (_messages.isNotEmpty && _messages[0].id == -1) {
        // 找到對應的服務器訊息
        Message? serverMessage;
        try {
          serverMessage = newMessages.firstWhere(
            (msg) => msg.content == _messages[0].content && !msg.isFromServer,
          );
        } catch (e) {
          // 如果找不到對應的訊息，serverMessage 會保持為 null
        }
        
        if (serverMessage != null) {
          // 更新臨時訊息的 ID
          _messages[0] = serverMessage;
          debugPrint('更新臨時訊息 ID: ${serverMessage.id}');
        } else {
          // 如果找不到對應的服務器訊息，移除臨時訊息
          _messages.removeAt(0);
          debugPrint('找不到對應的服務器訊息，移除臨時訊息');
        }
      }
      
      // Check if there are new messages we don't already have
      final hasNewMessages = _hasNewMessages(newMessages);
      final bool hasChanges = refresh || hasNewMessages;
      
      if (hasChanges) {
        if (refresh) {
          // 保留臨時訊息，只更新其他訊息
          final tempMessage = _messages.isNotEmpty && _messages[0].id == -1 ? _messages[0] : null;
          _messages = newMessages;
          if (tempMessage != null) {
            _messages.insert(0, tempMessage);
          }
        } else {
          // For regular updates, only add messages we don't already have
          final messagesMap = {for (var msg in _messages) msg.id: msg};
          int addedCount = 0;
          
          for (final message in newMessages) {
            if (!messagesMap.containsKey(message.id)) {
              _messages.add(message);
              addedCount++;
            }
          }
          
          // Sort messages by creation time to ensure proper ordering
          _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        
        _updateMessageIds();
        
        // Only update _hasMore flag, but don't increment _currentPage here
        _hasMore = response['next'] != null;
        
        // Notify listeners about the changes
        notifyListeners();
      }
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
        createdAt: DateTime.now(),
      );
      
      // Add the temporary message to the list immediately
      _messages.insert(0, tempMessage);
      notifyListeners();
      
      // Send the message to the server
      final response = await ApiConfig.sendMessage(content, isFromServer: isFromServer);
      
      debugPrint('訊息發送成功: ${response['message']}');
      
      // 等待一下再獲取最新訊息，確保服務器已處理
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Fetch messages to get the real message from server
      await fetchMessages(refresh: false);
      
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