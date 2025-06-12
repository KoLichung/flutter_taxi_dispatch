import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/user_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isProcessing = false;

  // 格式化手機號碼，只顯示前四碼和後三碼
  String formatPhone(String phone) {
    if (phone.length <= 7) return phone; // 手機號碼太短，直接顯示全部
    
    // 取得前四碼和後三碼
    String prefix = phone.substring(0, 4);
    String suffix = phone.substring(phone.length - 3);
    
    // 中間用星號代替
    String mask = '*' * (phone.length - 7);
    
    return '$prefix$mask$suffix';
  }

  // 發送郵件給管理員
  Future<void> _emailAdmin() async {
    const email = 'jason@kosbrother.com';
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=派車問題回報&body=您好，我有以下問題需要協助：',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        // 如果無法啟動郵件應用，顯示錯誤訊息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法啟動郵件應用')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $e')),
        );
      }
    }
  }

  // 確認刪除用戶對話框
  Future<void> _confirmDeleteUser() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('您確定要刪除您的帳號嗎？此操作無法恢復，您的所有數據將被永久刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _isProcessing = true;
      });

      try {
        debugPrint('開始刪除用戶流程');
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        
        debugPrint('調用 userProvider.deleteUser()');
        final success = await userProvider.deleteUser();
        debugPrint('刪除用戶結果: $success');
        
        if (success && mounted) {
          debugPrint('刪除成功，準備導航回登入頁面');
          // 刪除成功，返回登入頁面（用戶狀態已自動更新）
          Navigator.popUntil(context, (route) => route.isFirst);
        } else if (mounted) {
          debugPrint('刪除失敗，但沒有拋出異常');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('刪除用戶失敗，請稍後再試'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        debugPrint('刪除用戶過程中發生異常: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('刪除用戶失敗: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          debugPrint('刪除用戶流程結束，恢復按鈕狀態');
        }
      }
    } else {
      debugPrint('用戶取消了刪除操作');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('個人資訊'),
        backgroundColor: const Color(0xFF469030),
        foregroundColor: Colors.white,
      ),
      body: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          final user = userProvider.user;
          
          if (user == null) {
            return const Center(
              child: Text('請先登入'),
            );
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                // 用戶圖標
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Color(0xFF469030),
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),
                // 用戶基本資訊卡片
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildInfoItem(
                          icon: Icons.person, 
                          title: '姓名', 
                          value: user.name ?? '未設置'
                        ),
                        const Divider(),
                        _buildInfoItem(
                          icon: Icons.phone, 
                          title: '手機號碼', 
                          value: formatPhone(user.phone)
                        ),
                        const Divider(),
                        _buildInfoItem(
                          icon: Icons.face, 
                          title: '暱稱', 
                          value: user.nickName ?? '未設置'
                        ),
                        const Divider(),
                        _buildInfoItem(
                          icon: Icons.verified_user, 
                          title: '審核狀態', 
                          value: user.isTelegramBotEnable ? '已通過' : '尚未通過',
                          valueColor: user.isTelegramBotEnable ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // 通知管理員按鈕
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _emailAdmin,
                    icon: const Icon(Icons.email),
                    label: const Text('通知管理員'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF469030),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 刪除用戶按鈕
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _confirmDeleteUser,
                    icon: _isProcessing 
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ) 
                      : const Icon(Icons.delete_forever),
                    label: const Text('刪除用戶'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF469030), size: 24),
          const SizedBox(width: 12),
          Text(
            '$title:',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: valueColor,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
} 