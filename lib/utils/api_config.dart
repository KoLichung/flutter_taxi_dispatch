import 'api_service.dart';
import 'package:flutter/foundation.dart';

/// API configuration for the API
class ApiConfig {
  /// The base URL for the API
  static const String baseUrl = 'http://localhost:8000'; // Replace with actual API URL
  // static const String baseUrl = 'https://app.24hcartaiwan.com'; // Replace with actual API URL
  
  /// Get the API implementation
  static dynamic get api => ApiService;

  // Auth API
  static Future<dynamic> login(String phone, String password) {
    return ApiService.login(phone, password);
  }
  
  static Future<dynamic> register(String phone, String password, String name, String nickName) {
    return ApiService.register(phone, password, name, nickName);
  }
  
  // Messages API
  static Future<Map<String, dynamic>> getMessages({int page = 1, int pageSize = 20}) {
    return ApiService.getMessages(page: page, pageSize: pageSize);
  }
  
  static Future<Map<String, dynamic>> sendMessage(String content, {bool isFromServer = false}) {
    return ApiService.sendMessage(content, isFromServer: isFromServer);
  }
  
  static Future<void> deleteUser() {
    debugPrint('準備調用刪除用戶 API: 使用路徑 api/user/deleteuser/{用戶ID}/');
    return ApiService.deleteUser();
  }
} 