import 'package:flutter/foundation.dart';

class User {
  final int? id;
  final String phone;
  final String? name;
  final String? nickName;
  final bool isLoggedIn;
  final bool isTelegramBotEnable;

  User({
    this.id,
    required this.phone,
    this.name,
    this.nickName,
    this.isLoggedIn = false,
    this.isTelegramBotEnable = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    debugPrint('解析User JSON: is_telegram_bot_enable=${json['is_telegram_bot_enable']}');
    debugPrint('用戶JSON完整數據: $json');
    
    return User(
      id: json['id'],
      phone: json['phone'] ?? '',
      name: json['name'],
      nickName: json['nick_name'] ?? json['nickName'],
      isLoggedIn: json['isLoggedIn'] ?? false,
      isTelegramBotEnable: json['is_telegram_bot_enable'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'name': name,
      'nick_name': nickName,
      'isLoggedIn': isLoggedIn,
      'is_telegram_bot_enable': isTelegramBotEnable,
    };
  }

  User copyWith({
    int? id,
    String? phone,
    String? name,
    String? nickName,
    bool? isLoggedIn,
    bool? isTelegramBotEnable,
  }) {
    return User(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      nickName: nickName ?? this.nickName,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isTelegramBotEnable: isTelegramBotEnable ?? this.isTelegramBotEnable,
    );
  }
} 