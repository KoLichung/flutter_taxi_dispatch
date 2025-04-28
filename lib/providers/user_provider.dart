import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/api_config.dart';
import '../main.dart';  // 引入 main.dart 以使用 navigatorKey

class UserProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _loginError;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null && _user!.isLoggedIn;
  String? get loginError => _loginError;

  void clearLoginError() {
    if (_loginError != null) {
      _loginError = null;
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
      _user = User.fromJson(json.decode(userJson));
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', json.encode(_user!.toJson()));
    }
  }
} 