import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'providers/message_provider.dart';
import 'providers/case_message_provider.dart';
import 'screens/login_screen.dart';
import 'screens/message_screen.dart';
import 'screens/message_screen_animatedlist.dart';
import 'utils/push_notification_service.dart';

// 創建一個全局 NavigatorKey
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 創建一個全局 RouteObserver，用於監聽頁面的可見性變化
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 強制限制為直向
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // 初始化推播服務
  try {
    await PushNotificationService.initialize();
  } catch (e) {
    debugPrint('推播服務初始化失敗: $e');
    // 即使推播初始化失敗，app 仍可正常運作
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()..init()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
        ChangeNotifierProvider(create: (_) => CaseMessageProvider()),
      ],
      child: MaterialApp(
        title: '24H 叫車',
        debugShowCheckedModeBanner: false,
        // 使用全局 NavigatorKey
        navigatorKey: navigatorKey,
        // 註冊 RouteObserver 以監聽頁面可見性變化
        navigatorObservers: [routeObserver],
        // 本地化設置
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'TW'), // 繁體中文
          Locale('zh', 'CN'), // 簡體中文
          Locale('en', 'US'), // 英文
        ],
        locale: const Locale('zh', 'TW'), // 預設使用繁體中文
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF469030)),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => Consumer<UserProvider>(
            builder: (context, userProvider, _) {
              if (userProvider.isLoading) {
                return const SplashScreen();
              }
              return userProvider.isLoggedIn
                  ? const MessageScreen()
                  : const LoginScreen();
            },
          ),
          '/message': (context) => const MessageScreen(),
          '/login': (context) => const LoginScreen(),
        },
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF469030),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '24H 叫車',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
