import 'dart:convert';
import 'dart:async';
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
      // debugPrint('Using token: $token');
    }
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Token $token',
    };
  }
  
  // Authentication API
  static Future<User> login(String phone, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/dispatch/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'password': password,
      }),
    );
    
    if (response.statusCode == 200) {
      // Use utf8.decode to properly handle Chinese characters
      final responseBody = utf8.decode(response.bodyBytes);
      final userData = jsonDecode(responseBody);
      
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
      );
    } else {
      // 解析錯誤訊息
      String errorMessage;
      try {
        final responseBody = utf8.decode(response.bodyBytes);
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
  
  // Messages API
  static Future<Map<String, dynamic>> getMessages({int page = 1, int pageSize = 20}) async {
    final headers = await _getHeaders();
    try {
      // Always include unique timestamp to prevent caching
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Ensure we're fetching the latest messages with proper ordering
      final url = Uri.parse('$baseUrl/api/dispatch/messages/?page=$page&page_size=$pageSize&ordering=-created_at&_t=$timestamp&nocache=true');
      // debugPrint('Sending API request to get messages: ${url.toString()}');
      
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
      
      if (response.statusCode == 200) {
        // Use utf8.decode to properly handle Chinese characters
        final responseBody = utf8.decode(response.bodyBytes);
        // debugPrint('API response received at ${DateTime.now()}, length=${responseBody.length} bytes');
        // Log a snippet of the response for debugging
        if (responseBody.length > 0) {
          final preview = responseBody.length > 200 ? '${responseBody.substring(0, 200)}...' : responseBody;
          // debugPrint('Response preview: $preview');
        }
        
        final decodedResponse = jsonDecode(responseBody);
        
        // Log all message IDs to see what we're receiving
        if (decodedResponse['results'] != null && decodedResponse['results'].isNotEmpty) {
          final msgIds = decodedResponse['results'].map((m) => m['id']).toList();
          // debugPrint('All message IDs from API: $msgIds');
        }
        
        // debugPrint('Decoded messages: count=${decodedResponse['count']}, results=${decodedResponse['results']?.length ?? 0}');
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
} 