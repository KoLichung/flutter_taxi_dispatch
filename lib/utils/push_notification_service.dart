import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../main.dart';
import 'api_config.dart';
import '../providers/message_provider.dart';

// 背景訊息處理函數 (必須是頂層函數)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('收到背景推播: ${message.notification?.title}');
  debugPrint('推播內容: ${message.notification?.body}');
  debugPrint('推播資料: ${message.data}');
}

class PushNotificationService {
  static FirebaseMessaging messaging = FirebaseMessaging.instance;

  // 初始化推播服務
  static Future<void> initialize() async {
    try {
      debugPrint('初始化推播服務...');
      
      // 初始化 Firebase
      await Firebase.initializeApp();
      
      // 設定背景訊息處理
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      
      // 請求推播權限
      await requestPermission();
      
      // 設定前景訊息處理
      FirebaseMessaging.onMessage.listen(handleForegroundMessage);
      
      // 設定點擊通知處理
      FirebaseMessaging.onMessageOpenedApp.listen(handleNotificationTap);
      
      // 處理應用程式從終止狀態被通知喚醒的情況
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        handleNotificationTap(initialMessage);
      }
      
      // 設定預設通知聲音
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      
      // 監聽 token 變化（包括 APNS token 可用時）
      messaging.onTokenRefresh.listen((fcmToken) {
        debugPrint('FCM Token 更新: $fcmToken');
        // Token 更新時重新註冊設備
        registerFCMDevice();
      });
      
      // 註冊 FCM 設備
      await registerFCMDevice();
      
      // 執行推播設置測試
      await testNotificationSetup();
      
      debugPrint('推播服務初始化完成');
    } catch (e) {
      debugPrint('推播服務初始化失敗: $e');
    }
  }

  // 請求推播權限
  static Future<void> requestPermission() async {
    try {
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('推播權限狀態: ${settings.authorizationStatus}');
      debugPrint('Alert 權限: ${settings.alert}');
      debugPrint('Badge 權限: ${settings.badge}');
      debugPrint('Sound 權限: ${settings.sound}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('用戶授權推播通知');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('用戶授權臨時推播通知');
      } else {
        debugPrint('用戶拒絕推播通知 - 狀態: ${settings.authorizationStatus}');
        
        // 如果權限被拒絕，提示用戶手動開啟
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('推播權限被拒絕，請到設定中手動開啟');
        }
      }
    } catch (e) {
      debugPrint('請求推播權限失敗: $e');
    }
  }

  // 註冊 FCM 設備
  static Future<void> registerFCMDevice() async {
    try {
      // iOS 需要先確保 APNS token 可用
      if (Platform.isIOS) {
        debugPrint('iOS 平台，等待 APNS token...');
        
        // 嘗試取得 APNS token
        try {
          final apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) {
            debugPrint('APNS token 尚未可用，延遲註冊...');
            // 等待一段時間後重試
            await Future.delayed(const Duration(seconds: 2));
            final retryApnsToken = await messaging.getAPNSToken();
            if (retryApnsToken == null) {
              debugPrint('APNS token 仍然不可用，跳過 FCM 註冊');
              return;
            }
            debugPrint('重試後取得 APNS token: ${retryApnsToken.substring(0, 20)}...');
          } else {
            debugPrint('取得 APNS token: ${apnsToken.substring(0, 20)}...');
          }
        } catch (e) {
          debugPrint('取得 APNS token 失敗: $e');
          return;
        }
      }

      // 取得 FCM token
      final token = await messaging.getToken();
      if (token == null) {
        debugPrint('無法取得 FCM token');
        return;
      }

      // 取得設備 ID
      final deviceId = await getDeviceId();
      
      debugPrint('FCM Token: $token');
      debugPrint('Device ID: $deviceId');

      // 向後端註冊設備
      await ApiConfig.registerFCMDevice(
        registrationId: token,
        deviceId: deviceId,
        name: '24_dispatch',  // 固定為總機app
      );

      debugPrint('FCM 設備註冊成功');
    } catch (e) {
      debugPrint('FCM 設備註冊失敗: $e');
      
      // 如果是 APNS token 問題，嘗試延遲重試
      if (e.toString().contains('apns-token-not-set')) {
        debugPrint('APNS token 問題，5秒後重試...');
        Future.delayed(const Duration(seconds: 5), () {
          registerFCMDevice();
        });
      }
    }
  }

  // 取得設備 ID
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios_device';
    }
    
    return 'unknown_device';
  }

  // 處理前景推播訊息
  static void handleForegroundMessage(RemoteMessage message) {
    debugPrint('收到前景推播: ${message.notification?.title}');
    debugPrint('推播內容: ${message.notification?.body}');
    debugPrint('推播資料: ${message.data}');
    
    // 檢查是否在訊息畫面
    final isInMessageScreen = navigatorKey.currentContext != null && 
        ModalRoute.of(navigatorKey.currentContext!)?.settings.name == '/message';
    
    // 在前景顯示通知，但不在訊息畫面時才顯示
    if (message.notification != null && !isInMessageScreen) {
      showForegroundNotification(message);
    }
    
    // 在前景收到推播時，直接處理資料並重新載入訊息
    if (message.data.isNotEmpty) {
      refreshMessages();
    }
  }

  // 在前景顯示通知
  static void showForegroundNotification(RemoteMessage message) {
    if (navigatorKey.currentContext != null) {
      final context = navigatorKey.currentContext!;
      
      // 檢查是否在訊息畫面
      final isInMessageScreen = ModalRoute.of(context)?.settings.name == '/message';
      if (isInMessageScreen) return;
      
      // 使用 SnackBar 顯示通知
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.notification?.title != null)
                Text(
                  message.notification!.title!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              if (message.notification?.body != null)
                Text(
                  message.notification!.body!,
                  style: const TextStyle(color: Colors.white),
                ),
            ],
          ),
          backgroundColor: const Color(0xFF469030),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '查看',
            textColor: Colors.white,
            onPressed: () {
              refreshMessages();
            },
          ),
        ),
      );
    }
  }

  // 處理通知點擊
  static void handleNotificationTap(RemoteMessage message) {
    debugPrint('點擊推播通知: ${message.data}');
    
    // 根據通知資料執行相應動作
    final data = message.data;
    
    if (data['type'] == 'new_message') {
      // 導航到訊息畫面
      navigateToMessages();
    } else if (data['action'] == 'refresh_messages') {
      // 重新載入訊息
      refreshMessages();
    }
  }

  // 導航到訊息畫面
  static void navigateToMessages() {
    if (navigatorKey.currentContext != null) {
      // 導航到訊息畫面 (已經在訊息畫面中，所以不需要特殊導航)
      debugPrint('導航到訊息畫面');
      refreshMessages();
    }
  }

  // 重新載入訊息
  static void refreshMessages() {
    if (navigatorKey.currentContext != null) {
      try {
        // 使用 Provider 重新載入訊息
        final context = navigatorKey.currentContext!;
        final messageProvider = Provider.of<MessageProvider>(context, listen: false);
        messageProvider.fetchMessages(refresh: true);
        debugPrint('重新載入訊息成功');
      } catch (e) {
        debugPrint('重新載入訊息失敗: $e');
      }
    }
  }

  // 取得 FCM Token (用於調試)
  static Future<String?> getFCMToken() async {
    try {
      final token = await messaging.getToken();
      debugPrint('FCM Token: $token');
      return token;
    } catch (e) {
      debugPrint('取得 FCM Token 失敗: $e');
      return null;
    }
  }

  // 測試推播功能
  static Future<void> testNotificationSetup() async {
    debugPrint('=== 推播設置測試 ===');
    
    // 1. 檢查權限
    final settings = await messaging.getNotificationSettings();
    debugPrint('當前權限狀態: ${settings.authorizationStatus}');
    debugPrint('Alert: ${settings.alert}, Badge: ${settings.badge}, Sound: ${settings.sound}');
    
    // 2. 檢查 APNS token
    try {
      final apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null) {
        debugPrint('APNS Token 可用: ${apnsToken.substring(0, 20)}...');
      } else {
        debugPrint('APNS Token 不可用');
      }
    } catch (e) {
      debugPrint('取得 APNS Token 失敗: $e');
    }
    
    // 3. 檢查 FCM token
    final fcmToken = await getFCMToken();
    if (fcmToken != null) {
      debugPrint('FCM Token 可用: ${fcmToken.substring(0, 30)}...');
    }
    
    // 4. 檢查 Bundle ID
    debugPrint('Bundle ID: com.chijia.fluttertaxi24dispatch.flutterTaxi24Dispatch');
    
    debugPrint('=== 測試完成 ===');
  }
} 