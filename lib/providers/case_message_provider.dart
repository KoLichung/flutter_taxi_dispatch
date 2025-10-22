import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/case_message.dart';
import '../utils/api_service.dart';
import '../services/s3_upload_service.dart';

class CaseMessageProvider extends ChangeNotifier {
  List<CaseMessageListItem> _caseMessageList = [];
  List<CaseMessage> _currentCaseMessages = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  Timer? _autoRefreshTimer;
  
  // 用於防止分頁時列表重排的標記
  bool _isPaginating = false;

  List<CaseMessageListItem> get caseMessageList => _caseMessageList;
  List<CaseMessage> get currentCaseMessages => _currentCaseMessages;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  // 啟動自動刷新 timer（每 5 秒）
  void startAutoRefresh() {
    stopAutoRefresh(); // 先停止舊的 timer
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // 只有在不是正在分頁加載時才自動刷新第一頁
      if (!_isPaginating) {
        fetchCaseMessageList(refresh: false);
      }
    });
    debugPrint('案件消息自動刷新已啟動（每 5 秒）');
  }

  // 停止自動刷新
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    debugPrint('案件消息自動刷新已停止');
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }

  // 獲取案件消息列表（使用真實 API）
  Future<void> fetchCaseMessageList({bool refresh = true}) async {
    if (refresh) {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
      notifyListeners();
    }

    try {
      // 調用真實 API
      final response = await ApiService.getCaseMessageList(page: refresh ? 1 : _currentPage);
      
      final List<dynamic> results = response['results'] ?? [];
      final newList = results.map((e) => CaseMessageListItem.fromJson(e)).toList();

      if (refresh) {
        _caseMessageList = newList;
      } else {
        // 自動刷新時，智能合併數據，保持用戶的閱讀位置
        _mergeCaseMessageList(newList);
      }

      _hasMore = response['next'] != null;
    } catch (e) {
      debugPrint('獲取案件消息列表失敗: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 智能合併列表，避免影響用戶閱讀
  // 後端已按正確順序返回數據：有消息的按最後消息時間降序，無消息的按創建時間降序
  void _mergeCaseMessageList(List<CaseMessageListItem> newList) {
    if (_caseMessageList.isEmpty) {
      _caseMessageList = newList;
      return;
    }

    // 創建一個 Map 來快速查找現有項目
    final existingMap = {for (var item in _caseMessageList) item.id: item};

    // 使用新列表的數據，保持後端返回的順序
    final updatedList = <CaseMessageListItem>[];
    
    // 先添加新列表中的所有項目（保持順序）
    for (var newItem in newList) {
      updatedList.add(newItem);
      existingMap.remove(newItem.id); // 移除已處理的項目
    }
    
    // 將剩餘的舊項目添加到末尾（這些是在分頁時，新列表中沒有但舊列表中有的項目）
    updatedList.addAll(existingMap.values);

    _caseMessageList = updatedList;
  }

  // 加載更多案件（分頁）
  Future<void> loadMoreCases() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _isPaginating = true; // 標記正在分頁，暫停自動刷新的影響
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      final response = await ApiService.getCaseMessageList(page: nextPage);
      
      final List<dynamic> results = response['results'] ?? [];
      final moreData = results.map((e) => CaseMessageListItem.fromJson(e)).toList();

      if (moreData.isNotEmpty) {
        _caseMessageList.addAll(moreData);
        _currentPage = nextPage;
        _hasMore = response['next'] != null;
      } else {
        _hasMore = false;
      }
    } catch (e) {
      debugPrint('加載更多案件失敗: $e');
    } finally {
      _isLoadingMore = false;
      _isPaginating = false; // 取消分頁標記
      notifyListeners();
    }
  }

  // 獲取某個案件的消息列表（使用真實 API）
  Future<void> fetchCaseMessages(int caseId, {bool refresh = true}) async {
    if (refresh) {
      _isLoading = true;
      _currentCaseMessages = [];
      notifyListeners();
    }

    try {
      // 調用真實 API
      final response = await ApiService.getCaseMessages(caseId: caseId, page: 1);
      
      final List<dynamic> results = response['results'] ?? [];
      _currentCaseMessages = results.map((e) => CaseMessage.fromJson(e)).toList();
    } catch (e) {
      debugPrint('獲取案件消息失敗: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 發送文字消息（使用真實 API）
  Future<void> sendTextMessage(int caseId, String content) async {
    try {
      // 調用真實 API 發送消息
      final response = await ApiService.sendCaseTextMessage(
        caseId: caseId,
        content: content,
      );

      // 將服務器返回的消息添加到列表開頭
      final newMessage = CaseMessage.fromJson(response);
      _currentCaseMessages.insert(0, newMessage);
      
      notifyListeners();
      debugPrint('文字消息發送成功');
    } catch (e) {
      debugPrint('發送文字消息失敗: $e');
      rethrow;
    }
  }

  // 發送圖片消息（使用 S3 上傳）
  /// 
  /// 流程：
  /// 1. 上传图片到 S3
  /// 2. 调用后端创建图片消息记录
  /// 3. 更新本地消息列表
  Future<void> sendImageMessage({
    required int caseId,
    required File imageFile,
    required int userId,
    String? caption,
  }) async {
    try {
      debugPrint('開始發送圖片消息 (Case: $caseId)');
      
      // 1. 上传图片到 S3
      final uploadResult = await S3UploadService.uploadImage(
        imageFile: imageFile,
        caseId: caseId,
        userId: userId,
      );
      
      // 2. 调用后端创建图片消息记录
      final response = await ApiService.sendCaseImageMessage(
        caseId: caseId,
        imageKey: uploadResult['image_key']!,
        imageUrl: uploadResult['image_url']!,
        content: caption,
      );
      
      // 3. 更新本地消息列表
      final newMessage = CaseMessage.fromJson(response);
      _currentCaseMessages.insert(0, newMessage);
      notifyListeners();
      
      debugPrint('✅ 圖片消息發送成功 (ID: ${newMessage.id})');
    } catch (e) {
      debugPrint('❌ 發送圖片消息失敗: $e');
      rethrow;
    }
  }

  // 標記消息為已讀（使用真實 API）
  Future<void> markMessagesAsRead(int caseId) async {
    try {
      // 調用真實 API 標記已讀
      await ApiService.markCaseMessagesAsRead(caseId: caseId);

      // 本地更新案件列表中對應案件的未讀數（即時反應）
      for (int i = 0; i < _caseMessageList.length; i++) {
        if (_caseMessageList[i].id == caseId) {
          _caseMessageList[i] = CaseMessageListItem(
            id: _caseMessageList[i].id,
            caseNumber: _caseMessageList[i].caseNumber,
            caseState: _caseMessageList[i].caseState,
            driverName: _caseMessageList[i].driverName,
            driverNickName: _caseMessageList[i].driverNickName,
            dispatcherName: _caseMessageList[i].dispatcherName,
            dispatcherNickName: _caseMessageList[i].dispatcherNickName,
            latestMessage: _caseMessageList[i].latestMessage,
            unreadCount: 0, // 清零未讀數
            createTime: _caseMessageList[i].createTime,
          );
          break;
        }
      }

      notifyListeners();
      debugPrint('消息已標記為已讀');
    } catch (e) {
      debugPrint('標記已讀失敗: $e');
    }
  }
}

