import 'api_service.dart';

/// API configuration for the API
class ApiConfig {
  /// The base URL for the API
  static const String baseUrl = 'http://localhost:8000'; // Replace with actual API URL
//   static const String baseUrl = 'http://localhost:8000'; // Replace with actual API URL
  
  /// Get the API implementation
  static dynamic get api => ApiService;

  // Auth API
  static Future<dynamic> login(String phone, String password) {
    return ApiService.login(phone, password);
  }
  
  // Messages API
  static Future<Map<String, dynamic>> getMessages({int page = 1, int pageSize = 20}) {
    return ApiService.getMessages(page: page, pageSize: pageSize);
  }
  
  static Future<Map<String, dynamic>> sendMessage(String content, {bool isFromServer = false}) {
    return ApiService.sendMessage(content, isFromServer: isFromServer);
  }
} 