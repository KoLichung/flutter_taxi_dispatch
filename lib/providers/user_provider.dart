import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/api_config.dart';
import '../utils/push_notification_service.dart';
import '../main.dart';  // 引入 main.dart 以使用 navigatorKey

class UserProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _loginError;
  String? _registerError;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null && _user!.isLoggedIn;
  String? get loginError => _loginError;
  String? get registerError => _registerError;

  void clearLoginError() {
    if (_loginError != null) {
      _loginError = null;
      notifyListeners();
    }
  }

  void clearRegisterError() {
    if (_registerError != null) {
      _registerError = null;
      notifyListeners();
    }
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadUser();
    } catch (e) {
      debugPrint('Error initializing user: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    
    if (userJson != null) {
      debugPrint('從SharedPreferences加載用戶數據: $userJson');
      
      final Map<String, dynamic> userData = json.decode(userJson);
      debugPrint('用戶數據解析結果: $userData');
      debugPrint('審核狀態 (is_telegram_bot_enable): ${userData['is_telegram_bot_enable']}');
      
      _user = User.fromJson(userData);
      
      debugPrint('加載後的用戶審核狀態: ${_user?.isTelegramBotEnable}');
    } else {
      debugPrint('SharedPreferences中沒有找到用戶數據');
    }
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    _loginError = null;
    notifyListeners();

    try {
      final user = await ApiConfig.login(phone, password);
      _user = user;
      await _saveUser();
      
      // 確保等待一下，讓 token 完全保存
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 登入成功後嘗試註冊 FCM 設備
      try {
        await PushNotificationService.registerFCMDevice();
      } catch (e) {
        debugPrint('FCM 設備註冊失敗，但不影響登入: $e');
      }
      
      return true;
    } catch (e) {
      debugPrint('Error logging in: $e');
      
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring('Exception: '.length);
      }
      
      _loginError = errorMsg;
      
      _showErrorSnackBar(errorMsg);
      
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String phone, String password, String name, String nickName) async {
    _isLoading = true;
    _registerError = null;
    notifyListeners();

    try {
      final user = await ApiConfig.register(phone, password, name, nickName);
      // 註冊成功後自動登入
      _user = user;
      await _saveUser();
      return true;
    } catch (e) {
      debugPrint('Error registering: $e');
      
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring('Exception: '.length);
      }
      
      _registerError = errorMsg;
      
      _showErrorSnackBar(errorMsg);
      
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _showErrorSnackBar(String message) {
    if (navigatorKey.currentContext != null) {
      final context = navigatorKey.currentContext!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      debugPrint('顯示錯誤訊息 SnackBar: $message');
    } else {
      // 沒有可用的 BuildContext，只記錄錯誤
      debugPrint('無法顯示錯誤訊息: $message (沒有可用的 BuildContext)');
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user');
      _user = null;
    } catch (e) {
      debugPrint('Error logging out: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveUser() async {
    if (_user != null) {
      debugPrint('正在保存用戶信息到SharedPreferences');
      debugPrint('用戶ID: ${_user!.id}');
      debugPrint('用戶審核狀態 (isTelegramBotEnable): ${_user!.isTelegramBotEnable}');
      
      final userJson = json.encode(_user!.toJson());
      debugPrint('用戶JSON: $userJson');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', userJson);
      
      debugPrint('用戶信息已保存到SharedPreferences');
    }
  }

  Future<bool> deleteUser() async {
    _isLoading = true;
    notifyListeners();
    debugPrint('開始處理用戶刪除請求');

    try {
      debugPrint('調用 ApiConfig.deleteUser()');
      await ApiConfig.deleteUser();
      debugPrint('API 刪除用戶請求成功');
      
      debugPrint('清除本地用戶狀態');
      _user = null;
      // 用戶已自動登出
      
      debugPrint('用戶刪除流程完成');
      return true;
    } catch (e) {
      debugPrint('刪除用戶發生錯誤: $e');
      
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring('Exception: '.length);
        debugPrint('格式化錯誤訊息: $errorMsg');
      }
      
      debugPrint('顯示錯誤訊息');
      _showErrorSnackBar(errorMsg);
      
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
      debugPrint('刪除用戶處理完成，通知 UI 更新');
    }
  }


} 