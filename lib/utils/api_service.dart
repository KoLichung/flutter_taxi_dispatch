import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/message.dart';
import 'api_config.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;
  
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      debugPrint('Warning: No token found in SharedPreferences');
    } else {
      debugPrint('Using token: $token');
    }
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Token $token',
    };
    debugPrint('Generated headers: ${headers.keys.join(', ')}');
    return headers;
  }
  
  // Authentication API
  static Future<User> login(String phone, String password) async {
    debugPrint('開始發送登入請求到: $baseUrl/api/dispatch/login/');
    debugPrint('請求參數: phone=$phone, password=***');
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/dispatch/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'password': password,
      }),
    );
    
    debugPrint('登入 API 響應狀態碼: ${response.statusCode}');
    debugPrint('登入 API 響應標頭: ${response.headers}');
    
    // 使用utf8.decode處理響應數據，以正確處理中文字符
    final responseBody = utf8.decode(response.bodyBytes);
    debugPrint('登入 API 完整響應內容: $responseBody');
    
    if (response.statusCode == 200) {
      final userData = jsonDecode(responseBody);
      
      // 詳細記錄關鍵欄位
      debugPrint('登入成功，用戶ID: ${userData['id']}');
      debugPrint('用戶名稱: ${userData['name']}');
      debugPrint('用戶暱稱: ${userData['nick_name']}');
      debugPrint('審核狀態 (is_telegram_bot_enable): ${userData['is_telegram_bot_enable']}');
      
      // Save token if provided
      if (userData['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', userData['token']);
        debugPrint('Token saved: ${userData['token']}');
      } else {
        debugPrint('Warning: No token received from server');
      }
      
      return User(
        id: userData['id'],
        phone: userData['phone'],
        name: userData['name'],
        nickName: userData['nick_name'],
        isLoggedIn: true,
        isTelegramBotEnable: userData['is_telegram_bot_enable'] ?? false,
      );
    } else {
      // 解析錯誤訊息
      String errorMessage;
      try {
        final errorData = jsonDecode(responseBody);
        errorMessage = errorData['error'] ?? '登入失敗';
        debugPrint('Login error: $errorMessage');
      } catch (e) {
        errorMessage = '登入失敗';
        debugPrint('Cannot parse error response: $e');
      }
      
      // 根據狀態碼返回不同錯誤
      switch (response.statusCode) {
        case 400:
          throw Exception('請提供正確的帳號和密碼');
        case 401:
          throw Exception('帳號或密碼錯誤');
        case 403:
          throw Exception(errorMessage); // 直接使用服務器返回的錯誤訊息，如"您沒有派單的權限"
        default:
          throw Exception('登入失敗: ${response.statusCode}');
      }
    }
  }
  
  static Future<User> register(String phone, String password, String name, String nickName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/user/create/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'password': password,
        'name': name,
        'nick_name': nickName,
        'car_team': 1,  // 固定為 1
      }),
    );
    
    if (response.statusCode == 201) {
      // 註冊成功後自動登入
      return await login(phone, password);
    } else {
      // 解析錯誤訊息
      String errorMessage;
      try {
        final responseBody = utf8.decode(response.bodyBytes);
        final errorData = jsonDecode(responseBody);
        
        // API可能返回不同格式的錯誤
        if (errorData['error'] != null) {
          errorMessage = errorData['error'];
        } else if (errorData['detail'] != null) {
          errorMessage = errorData['detail'];
        } else if (errorData is Map) {
          // 可能是欄位錯誤
          final fieldErrors = <String>[];
          errorData.forEach((key, value) {
            if (value is List && value.isNotEmpty) {
              fieldErrors.add('$key: ${value.join(', ')}');
            } else if (value is String) {
              fieldErrors.add('$key: $value');
            }
          });
          errorMessage = fieldErrors.join('\n');
        } else {
          errorMessage = '註冊失敗';
        }
        
        debugPrint('Registration error: $errorMessage');
      } catch (e) {
        errorMessage = '註冊失敗';
        debugPrint('Cannot parse error response: $e');
      }
      
      // 根據狀態碼返回不同錯誤
      switch (response.statusCode) {
        case 400:
          throw Exception(errorMessage);
        case 409:
          throw Exception('此手機號碼已被使用');
        default:
          throw Exception('註冊失敗: ${response.statusCode}');
      }
    }
  }
  
  // Messages API
  static Future<Map<String, dynamic>> getMessages({int page = 1, int pageSize = 20}) async {
    final headers = await _getHeaders();
    try {
      // Always include unique timestamp to prevent caching
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Ensure we're fetching the latest messages with proper ordering
      final url = Uri.parse('$baseUrl/api/dispatch/messages/?page=$page&page_size=$pageSize&ordering=-created_at&_t=$timestamp&nocache=true');
      
      debugPrint('=== 獲取系統消息列表 ===');
      debugPrint('URL: ${url.toString()}');
      
      // Add additional no-cache headers
      final requestHeaders = {
        ...headers,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      };
      
      final response = await http.get(
        url,
        headers: requestHeaders,
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('回應狀態碼: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Use utf8.decode to properly handle Chinese characters
        final responseBody = utf8.decode(response.bodyBytes);
        
        final decodedResponse = jsonDecode(responseBody);
        
        // 打印案件消息未讀數
        if (decodedResponse.containsKey('case_message_unread_count')) {
          debugPrint('案件消息未讀數 (case_message_unread_count): ${decodedResponse['case_message_unread_count']}');
        }
        
        debugPrint('獲取系統消息成功: ${decodedResponse['count']} 條消息');
        
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('獲取訊息失敗: 401 - 請重新登入');
      } else {
        debugPrint('Error response from server: ${response.statusCode} - ${response.body}');
        throw Exception('獲取訊息失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API request timed out when fetching messages');
      throw Exception('獲取訊息逾時，請檢查網路連線');
    } catch (e) {
      debugPrint('Error in getMessages: $e');
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> sendMessage(String content, {bool isFromServer = false}) async {
    final headers = await _getHeaders();
    try {
      debugPrint('Sending message to API: "${content.substring(0, content.length > 30 ? 30 : content.length)}..."');
      final response = await http.post(
        Uri.parse('$baseUrl/api/dispatch/messages/'),
        headers: headers,
        body: jsonEncode({
          'content': content,
          'is_from_server': isFromServer,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 201) {
        // Use utf8.decode to properly handle Chinese characters
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        debugPrint('Message sent successfully, server returned ID: ${decodedResponse['id']}');
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('發送訊息失敗: 401 - 請重新登入');
      } else {
        debugPrint('Error response from server: ${response.statusCode} - ${response.body}');
        throw Exception('發送訊息失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API request timed out when sending message');
      throw Exception('發送訊息逾時，請檢查網路連線');
    } catch (e) {
      debugPrint('Error in sendMessage: $e');
      rethrow;
    }
  }
  
  // Search Messages API
  static Future<Map<String, dynamic>> searchMessages(String query, {int page = 1, int pageSize = 20}) async {
    final headers = await _getHeaders();
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$baseUrl/api/dispatch/messages/?q=${Uri.encodeComponent(query)}');
      
      // 詳細記錄請求信息
      debugPrint('=== Search Messages API Request ===');
      debugPrint('URL: ${url.toString()}');
      debugPrint('Method: GET');
      debugPrint('Query: "$query"');
      debugPrint('Encoded Query: "${Uri.encodeComponent(query)}"');
      
      final requestHeaders = {
        ...headers,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      };
      
      debugPrint('Request Headers:');
      requestHeaders.forEach((key, value) {
        if (key == 'Authorization') {
          debugPrint('  $key: ${value.substring(0, 15)}...'); // 只顯示部分token
        } else {
          debugPrint('  $key: $value');
        }
      });
      debugPrint('=====================================');
      
      final response = await http.get(
        url,
        headers: requestHeaders,
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('=== Search Messages API Response ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');
      
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        debugPrint('Response Body Length: ${responseBody.length} bytes');
        final decodedResponse = jsonDecode(responseBody);
        
        // 新的API回應格式：直接返回訊息數組
        if (decodedResponse is List) {
          debugPrint('Search completed: found ${decodedResponse.length} messages');
          debugPrint('====================================');
          
          // 轉換為與其他API一致的格式
          return {
            'count': decodedResponse.length,
            'results': decodedResponse,
          };
        } else {
          // 如果不是數組，可能是舊格式，直接返回
          debugPrint('Search completed: found ${decodedResponse['results']?.length ?? 0} messages');
          debugPrint('Total count: ${decodedResponse['count'] ?? 'unknown'}');
          debugPrint('====================================');
          return decodedResponse;
        }
      } else {
        final responseBody = utf8.decode(response.bodyBytes);
        debugPrint('Error Response Body: $responseBody');
        debugPrint('====================================');
        
        if (response.statusCode == 401) {
          throw Exception('搜索訊息失敗: 401 - 請重新登入');
        } else if (response.statusCode == 403) {
          throw Exception('搜索訊息失敗: 403 - 權限不足或認證失敗');
        } else {
          throw Exception('搜索訊息失敗: ${response.statusCode}');
        }
      }
    } on TimeoutException {
      debugPrint('API request timed out when searching messages');
      throw Exception('搜索訊息逾時，請檢查網路連線');
    } catch (e) {
      debugPrint('Error in searchMessages: $e');
      rethrow;
    }
  }
  
  static Future<void> deleteUser() async {
    final headers = await _getHeaders();
    try {
      // 首先獲取當前用戶的ID
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      
      if (userJson == null) {
        throw Exception('找不到用戶信息，無法刪除用戶');
      }
      
      final userData = jsonDecode(userJson);
      final userId = userData['id'];
      
      if (userId == null) {
        throw Exception('用戶ID不存在，無法刪除用戶');
      }
      
      debugPrint('正在發送刪除用戶請求到: $baseUrl/api/user/deleteuser/$userId/');
      debugPrint('請求標頭: $headers');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/api/user/deleteuser/$userId/'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('刪除用戶 API 響應狀態碼: ${response.statusCode}');
      debugPrint('刪除用戶 API 響應標頭: ${response.headers}');
      
      // 記錄完整的回應數據，以便診斷問題
      final responseBody = utf8.decode(response.bodyBytes);
      debugPrint('刪除用戶 API 完整響應內容: $responseBody');
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('刪除用戶成功，正在清除本地存儲');
        // 刪除成功，清除本地存儲的 token 和用戶信息
        await prefs.remove('token');
        await prefs.remove('user');
        debugPrint('本地存儲清除完成');
        return;
      } else {
        // 解析錯誤訊息
        String errorMessage;
        try {
          final errorData = jsonDecode(responseBody);
          errorMessage = errorData['error'] ?? errorData['detail'] ?? '刪除用戶失敗';
          debugPrint('解析的錯誤消息: $errorMessage');
        } catch (e) {
          errorMessage = '刪除用戶失敗: ${response.statusCode}';
          debugPrint('無法解析錯誤響應: $e');
          debugPrint('原始響應內容: $responseBody');
          
          // 檢查是否為 HTML 回應，這通常是伺服器錯誤的徵兆
          if (responseBody.trim().startsWith('<!DOCTYPE') || responseBody.trim().startsWith('<html')) {
            debugPrint('伺服器返回了 HTML 內容，可能是服務器端錯誤或 API 路徑不正確');
            errorMessage = '刪除用戶失敗: 伺服器錯誤 (${response.statusCode})';
          }
        }
        
        throw Exception(errorMessage);
      }
    } on TimeoutException {
      debugPrint('刪除用戶請求超時');
      throw Exception('刪除用戶逾時，請檢查網路連線');
    } catch (e) {
      debugPrint('刪除用戶發生錯誤: $e');
      
      if (e is FormatException) {
        debugPrint('格式錯誤: $e');
      } else if (e is http.ClientException) {
        debugPrint('HTTP 客戶端錯誤: $e');
      }
      
      rethrow;
    }
  }

  // FCM 設備註冊
  static Future<Map<String, dynamic>> registerFCMDevice({
    required String registrationId,
    required String deviceId,
    String? type,  // 改為可選參數，讓函數內部自動判斷
    String name = '24_dispatch',  // 固定為總機app
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token == null) {
      throw Exception('用戶未登入');
    }

    // 如果沒有提供 type，根據平台自動判斷
    String deviceType = type ?? (Platform.isAndroid ? 'android' : 'ios');

    debugPrint('註冊 FCM 設備: deviceId=$deviceId, type=$deviceType, name=$name');

    final response = await http.post(
      Uri.parse('$baseUrl/fcm/device_register'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: json.encode({
        'registration_id': registrationId,
        'device_id': deviceId,
        'type': deviceType,
        'name': name,
      }),
    );

    debugPrint('FCM 註冊回應狀態: ${response.statusCode}');
    debugPrint('FCM 註冊回應內容: ${response.body}');

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorBody = json.decode(response.body);
      throw Exception(errorBody['message'] ?? 'FCM 設備註冊失敗');
    }
  }

  // ========== 案件消息 API ==========

  // 獲取案件消息列表（聊天列表頁）
  static Future<Map<String, dynamic>> getCaseMessageList({int page = 1}) async {
    final headers = await _getHeaders();
    try {
      final url = Uri.parse('$baseUrl/api/dispatch/case-messages/?page=$page');
      
      debugPrint('=== 獲取案件消息列表 ===');
      debugPrint('URL: ${url.toString()}');
      
      final requestHeaders = {
        ...headers,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      };
      
      final response = await http.get(
        url,
        headers: requestHeaders,
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('回應狀態碼: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        debugPrint('獲取案件列表成功: ${decodedResponse['count']} 個案件');
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('獲取案件列表失敗: 401 - 請重新登入');
      } else {
        debugPrint('錯誤回應: ${response.statusCode} - ${response.body}');
        throw Exception('獲取案件列表失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API 請求超時');
      throw Exception('獲取案件列表超時，請檢查網路連線');
    } catch (e) {
      debugPrint('獲取案件列表錯誤: $e');
      rethrow;
    }
  }

  // 獲取某個案件的消息列表
  static Future<Map<String, dynamic>> getCaseMessages({
    required int caseId,
    int page = 1,
  }) async {
    final headers = await _getHeaders();
    try {
      final url = Uri.parse('$baseUrl/api/dispatch/cases/$caseId/messages/?page=$page');
      
      debugPrint('=== 獲取案件消息 ===');
      debugPrint('Case ID: $caseId, Page: $page');
      debugPrint('URL: ${url.toString()}');
      
      final requestHeaders = {
        ...headers,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      };
      
      final response = await http.get(
        url,
        headers: requestHeaders,
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('回應狀態碼: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        debugPrint('獲取案件消息成功: ${decodedResponse['count']} 條消息');
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('獲取案件消息失敗: 401 - 請重新登入');
      } else if (response.statusCode == 404) {
        throw Exception('案件不存在');
      } else {
        debugPrint('錯誤回應: ${response.statusCode} - ${response.body}');
        throw Exception('獲取案件消息失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API 請求超時');
      throw Exception('獲取案件消息超時，請檢查網路連線');
    } catch (e) {
      debugPrint('獲取案件消息錯誤: $e');
      rethrow;
    }
  }

  // 發送文字消息到案件
  static Future<Map<String, dynamic>> sendCaseTextMessage({
    required int caseId,
    required String content,
  }) async {
    final headers = await _getHeaders();
    try {
      debugPrint('=== 發送案件文字消息 ===');
      debugPrint('Case ID: $caseId');
      debugPrint('Content: ${content.substring(0, content.length > 30 ? 30 : content.length)}...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/dispatch/cases/$caseId/messages/'),
        headers: headers,
        body: jsonEncode({
          'message_type': 'text',
          'content': content,
        }),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('回應狀態碼: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        debugPrint('消息發送成功，ID: ${decodedResponse['id']}');
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('發送消息失敗: 401 - 請重新登入');
      } else if (response.statusCode == 404) {
        throw Exception('案件不存在');
      } else {
        debugPrint('錯誤回應: ${response.statusCode} - ${response.body}');
        throw Exception('發送消息失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API 請求超時');
      throw Exception('發送消息超時，請檢查網路連線');
    } catch (e) {
      debugPrint('發送消息錯誤: $e');
      rethrow;
    }
  }

  // 標記案件消息為已讀
  static Future<Map<String, dynamic>> markCaseMessagesAsRead({
    required int caseId,
  }) async {
    final headers = await _getHeaders();
    try {
      debugPrint('=== 標記案件消息為已讀 ===');
      debugPrint('Case ID: $caseId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/dispatch/cases/$caseId/messages/mark-read/'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('回應狀態碼: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        debugPrint('標記已讀成功: ${decodedResponse['updated_count']} 條消息');
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('標記已讀失敗: 401 - 請重新登入');
      } else if (response.statusCode == 404) {
        throw Exception('案件不存在');
      } else {
        debugPrint('錯誤回應: ${response.statusCode} - ${response.body}');
        throw Exception('標記已讀失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API 請求超時');
      throw Exception('標記已讀超時，請檢查網路連線');
    } catch (e) {
      debugPrint('標記已讀錯誤: $e');
      rethrow;
    }
  }

  // 獲取案件未讀消息數
  static Future<int> getCaseUnreadCount({
    required int caseId,
  }) async {
    final headers = await _getHeaders();
    try {
      final url = Uri.parse('$baseUrl/api/dispatch/cases/$caseId/messages/unread-count/');
      
      final response = await http.get(
        url,
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        return decodedResponse['unread_count'] ?? 0;
      } else {
        debugPrint('獲取未讀數失敗: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      debugPrint('獲取未讀數錯誤: $e');
      return 0;
    }
  }

  // 發送圖片消息到案件
  static Future<Map<String, dynamic>> sendCaseImageMessage({
    required int caseId,
    required String imageKey,
    required String imageUrl,
    String? content,
  }) async {
    final headers = await _getHeaders();
    try {
      debugPrint('=== 發送案件圖片消息 ===');
      debugPrint('Case ID: $caseId');
      debugPrint('Image Key: $imageKey');
      debugPrint('Image URL: $imageUrl');
      debugPrint('Content: ${content ?? ""}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/dispatch/cases/$caseId/messages/'),
        headers: headers,
        body: jsonEncode({
          'message_type': 'image',
          'image_key': imageKey,
          'image_url': imageUrl,
          'content': content ?? '', // 圖片訊息不顯示文字
        }),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('回應狀態碼: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        final responseBody = utf8.decode(response.bodyBytes);
        final decodedResponse = jsonDecode(responseBody);
        debugPrint('圖片消息發送成功，ID: ${decodedResponse['id']}');
        return decodedResponse;
      } else if (response.statusCode == 401) {
        throw Exception('發送圖片消息失敗: 401 - 請重新登入');
      } else if (response.statusCode == 404) {
        throw Exception('案件不存在');
      } else {
        debugPrint('錯誤回應: ${response.statusCode} - ${response.body}');
        throw Exception('發送圖片消息失敗: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('API 請求超時');
      throw Exception('發送圖片消息超時，請檢查網路連線');
    } catch (e) {
      debugPrint('發送圖片消息錯誤: $e');
      rethrow;
    }
  }


} 