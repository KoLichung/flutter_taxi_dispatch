import 'dart:async';
import 'package:flutter/material.dart';
import '../models/case_message.dart';

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

  // 獲取案件消息列表（使用 fake data）
  Future<void> fetchCaseMessageList({bool refresh = true}) async {
    if (refresh) {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
      notifyListeners();
    }

    try {
      // 模擬 API 請求延遲
      await Future.delayed(const Duration(milliseconds: 500));

      // Fake data
      final fakeData = _generateFakeCaseMessageList();

      if (refresh) {
        _caseMessageList = fakeData;
      } else {
        // 自動刷新時，智能合併數據，保持用戶的閱讀位置
        _mergeCaseMessageList(fakeData);
      }

      _hasMore = fakeData.length >= 20; // 假設有更多數據
    } catch (e) {
      debugPrint('獲取案件消息列表失敗: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 智能合併列表，避免影響用戶閱讀
  void _mergeCaseMessageList(List<CaseMessageListItem> newList) {
    if (_caseMessageList.isEmpty) {
      _caseMessageList = newList;
      return;
    }

    // 創建一個 Map 來快速查找現有項目
    final existingMap = {for (var item in _caseMessageList) item.id: item};

    // 更新或添加新項目
    final updatedList = <CaseMessageListItem>[];
    for (var newItem in newList) {
      if (existingMap.containsKey(newItem.id)) {
        // 更新現有項目
        updatedList.add(newItem);
      } else {
        // 新項目，添加到開頭
        updatedList.insert(0, newItem);
      }
    }

    // 保留不在新列表中但在舊列表中的項目（如果用戶正在查看第二頁）
    for (var oldItem in _caseMessageList) {
      if (!newList.any((item) => item.id == oldItem.id)) {
        updatedList.add(oldItem);
      }
    }

    _caseMessageList = updatedList;
  }

  // 加載更多案件（分頁）
  Future<void> loadMoreCases() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _isPaginating = true; // 標記正在分頁，暫停自動刷新的影響
    notifyListeners();

    try {
      // 模擬 API 請求延遲
      await Future.delayed(const Duration(milliseconds: 800));

      final nextPage = _currentPage + 1;
      final moreData = _generateFakeCaseMessageList(page: nextPage);

      if (moreData.isNotEmpty) {
        _caseMessageList.addAll(moreData);
        _currentPage = nextPage;
        _hasMore = moreData.length >= 20;
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

  // 獲取某個案件的消息列表（使用 fake data）
  Future<void> fetchCaseMessages(int caseId, {bool refresh = true}) async {
    if (refresh) {
      _isLoading = true;
      _currentCaseMessages = [];
      notifyListeners();
    }

    try {
      // 模擬 API 請求延遲
      await Future.delayed(const Duration(milliseconds: 500));

      // Fake data
      _currentCaseMessages = _generateFakeCaseMessages(caseId);
    } catch (e) {
      debugPrint('獲取案件消息失敗: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 發送文字消息（使用 fake data）
  Future<void> sendTextMessage(int caseId, String content) async {
    try {
      // 創建臨時消息
      final tempMessage = CaseMessage(
        id: -1,
        caseId: caseId,
        sender: 101, // 假設當前用戶 ID 是 101
        senderName: '李派单',
        senderNickName: '小李',
        messageType: 'text',
        content: content,
        isRead: true,
        createdAt: DateTime.now(),
      );

      // 立即添加到列表
      _currentCaseMessages.insert(0, tempMessage);
      notifyListeners();

      // 模擬 API 請求延遲
      await Future.delayed(const Duration(milliseconds: 500));

      // 更新為真實 ID
      _currentCaseMessages[0] = CaseMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        caseId: caseId,
        sender: 101,
        senderName: '李派单',
        senderNickName: '小李',
        messageType: 'text',
        content: content,
        isRead: true,
        createdAt: DateTime.now(),
      );

      notifyListeners();
      debugPrint('文字消息發送成功');
    } catch (e) {
      debugPrint('發送文字消息失敗: $e');
      // 移除臨時消息
      if (_currentCaseMessages.isNotEmpty && _currentCaseMessages[0].id == -1) {
        _currentCaseMessages.removeAt(0);
        notifyListeners();
      }
      rethrow;
    }
  }

  // 發送圖片消息（使用 fake data）
  Future<void> sendImageMessage(int caseId, String imageUrl, String? caption) async {
    try {
      // 創建臨時消息
      final tempMessage = CaseMessage(
        id: -1,
        caseId: caseId,
        sender: 101,
        senderName: '李派单',
        senderNickName: '小李',
        messageType: 'image',
        content: caption ?? '發送了一張圖片',
        imageUrl: imageUrl,
        isRead: true,
        createdAt: DateTime.now(),
      );

      // 立即添加到列表
      _currentCaseMessages.insert(0, tempMessage);
      notifyListeners();

      // 模擬上傳延遲
      await Future.delayed(const Duration(seconds: 2));

      // 更新為真實消息
      _currentCaseMessages[0] = CaseMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        caseId: caseId,
        sender: 101,
        senderName: '李派单',
        senderNickName: '小李',
        messageType: 'image',
        content: caption ?? '發送了一張圖片',
        imageUrl: imageUrl,
        isRead: true,
        createdAt: DateTime.now(),
      );

      notifyListeners();
      debugPrint('圖片消息發送成功');
    } catch (e) {
      debugPrint('發送圖片消息失敗: $e');
      // 移除臨時消息
      if (_currentCaseMessages.isNotEmpty && _currentCaseMessages[0].id == -1) {
        _currentCaseMessages.removeAt(0);
        notifyListeners();
      }
      rethrow;
    }
  }

  // 標記消息為已讀（使用 fake data）
  Future<void> markMessagesAsRead(int caseId) async {
    try {
      // 模擬 API 請求
      await Future.delayed(const Duration(milliseconds: 200));

      // 更新當前消息列表中的未讀狀態
      for (int i = 0; i < _currentCaseMessages.length; i++) {
        if (!_currentCaseMessages[i].isRead) {
          _currentCaseMessages[i] = CaseMessage(
            id: _currentCaseMessages[i].id,
            caseId: _currentCaseMessages[i].caseId,
            sender: _currentCaseMessages[i].sender,
            senderName: _currentCaseMessages[i].senderName,
            senderNickName: _currentCaseMessages[i].senderNickName,
            messageType: _currentCaseMessages[i].messageType,
            content: _currentCaseMessages[i].content,
            imageUrl: _currentCaseMessages[i].imageUrl,
            imageKey: _currentCaseMessages[i].imageKey,
            isRead: true,
            readAt: DateTime.now(),
            createdAt: _currentCaseMessages[i].createdAt,
          );
        }
      }

      // 更新案件列表中對應案件的未讀數
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

  // ========== Fake Data 生成器 ==========

  List<CaseMessageListItem> _generateFakeCaseMessageList({int page = 1}) {
    final now = DateTime.now();
    final items = <CaseMessageListItem>[];

    // 根據頁碼生成不同的數據
    final startId = (page - 1) * 20 + 1;

    for (int i = 0; i < 20; i++) {
      final id = startId + i;
      final minutesAgo = i * 5;

      items.add(CaseMessageListItem(
        id: id,
        caseNumber: '高雄車隊 ❤️${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.${id.toString().padLeft(3, '0')}❤️',
        caseState: ['way_to_catch', 'on_road', 'arrived', 'completed'][i % 4],
        driverName: ['王司机', '張司机', '李司机', '陳司机'][i % 4],
        driverNickName: ['老王', '小張', '阿李', '小陳'][i % 4],
        dispatcherName: '李派单',
        dispatcherNickName: '小李',
        latestMessage: LatestMessage(
          id: 1000 + id,
          messageType: i % 5 == 0 ? 'image' : 'text',
          content: [
            '已到達上車點',
            '客人還沒到，我再等一下',
            '客人上車了，出發中',
            '這是位置照片',
            '已送達目的地',
          ][i % 5],
          imageUrl: i % 5 == 0
              ? 'https://picsum.photos/200/300?random=$id'
              : null,
          senderId: 789 + i,
          senderName: ['王司机', '張司机', '李司机', '陳司机'][i % 4],
          createdAt: now.subtract(Duration(minutes: minutesAgo)),
        ),
        unreadCount: i % 3, // 0, 1, 2 循環
        createTime: now.subtract(Duration(hours: i)),
      ));
    }

    return items;
  }

  List<CaseMessage> _generateFakeCaseMessages(int caseId) {
    final now = DateTime.now();
    final messages = <CaseMessage>[];

    for (int i = 0; i < 15; i++) {
      final isFromDriver = i % 2 == 0;
      final minutesAgo = i * 3;

      messages.add(CaseMessage(
        id: 5000 + i,
        caseId: caseId,
        sender: isFromDriver ? 789 : 101,
        senderName: isFromDriver ? '王司机' : '李派单',
        senderNickName: isFromDriver ? '老王' : '小李',
        messageType: i % 6 == 0 ? 'image' : 'text',
        content: isFromDriver
            ? [
                '收到，正在前往',
                '路上有點塞車，可能會晚 5 分鐘',
                '已到達上車點',
                '客人上車了',
                '這是位置照片',
                '已送達目的地',
              ][i % 6]
            : [
                '請問到了嗎？',
                '好的，謝謝',
                '客人可能會晚一點',
                '麻煩注意一下',
                '收到照片了',
                '辛苦了',
              ][i % 6],
        imageUrl: i % 6 == 0 ? 'https://picsum.photos/400/300?random=$i' : null,
        isRead: i > 2, // 前 3 條未讀
        readAt: i > 2 ? now.subtract(Duration(minutes: minutesAgo - 1)) : null,
        createdAt: now.subtract(Duration(minutes: minutesAgo)),
      ));
    }

    // 反轉順序，最新的在前面
    return messages.reversed.toList();
  }
}

