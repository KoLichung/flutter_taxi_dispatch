import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/case_message.dart';
import '../providers/case_message_provider.dart';
import '../providers/user_provider.dart';

class CaseMessageDetailScreen extends StatefulWidget {
  final int caseId;
  final String caseNumber;

  const CaseMessageDetailScreen({
    super.key,
    required this.caseId,
    required this.caseNumber,
  });

  @override
  State<CaseMessageDetailScreen> createState() =>
      _CaseMessageDetailScreenState();
}

class _CaseMessageDetailScreenState extends State<CaseMessageDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isKeyboardVisible = false;
  
  // 全域變數存儲 EditableTextState
  EditableTextState? _currentEditableTextState;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider =
          Provider.of<CaseMessageProvider>(context, listen: false);
      provider.fetchCaseMessages(widget.caseId, refresh: true);
      
      // 標記消息為已讀
      provider.markMessagesAsRead(widget.caseId);
      
      // 滾動到底部
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _scrollController.hasClients) {
          _scrollToBottom();
        }
      });
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    _messageController.clear();

    try {
      final provider =
          Provider.of<CaseMessageProvider>(context, listen: false);
      await provider.sendTextMessage(widget.caseId, message);

      // 滾動到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發送訊息失敗: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      // 顯示選擇來源對話框
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('選擇圖片來源'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('相機'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('相簿'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      // 選擇圖片
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      // 在實際應用中，這裡需要：
      // 1. 調用 API 獲取上傳 URL
      // 2. 上傳圖片到 S3
      // 3. 調用 API 創建圖片消息記錄

      // 現在使用 fake data 模擬
      final provider =
          Provider.of<CaseMessageProvider>(context, listen: false);
      
      // 顯示上傳中提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在上傳圖片...')),
        );
      }

      await provider.sendImageMessage(
        widget.caseId,
        image.path, // 在實際應用中這應該是 S3 URL
        '發送了一張圖片',
      );

      // 滾動到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom();
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('圖片發送成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發送圖片失敗: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  // 自定義文字選擇選單
  Widget _buildContextMenu(
      BuildContext context, EditableTextState editableTextState) {
    final List<ContextMenuButtonItem> buttonItems = [];
    final TextEditingController controller =
        editableTextState.widget.controller!;
    final TextSelection selection =
        editableTextState.currentTextEditingValue.selection;

    // 只有在沒有選中文字時，才顯示"全選"和"選取"按鈕
    if (selection.isCollapsed) {
      // 全選
      if (controller.text.isNotEmpty) {
        buttonItems.add(
          ContextMenuButtonItem(
            label: '全選',
            onPressed: () {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (editableTextState.mounted) {
                    editableTextState.showToolbar();
                  }
                });
              });
            },
          ),
        );
      }

      if (controller.text.isNotEmpty) {
        buttonItems.add(
          ContextMenuButtonItem(
            label: '選擇',
            onPressed: () {
              final cursorOffset = selection.baseOffset;
              final text = controller.text;

              int lineStart = cursorOffset;
              while (lineStart > 0 && text[lineStart - 1] != '\n') {
                lineStart--;
              }

              int lineEnd = cursorOffset;
              while (lineEnd < text.length && text[lineEnd] != '\n') {
                lineEnd++;
              }

              controller.selection = TextSelection(
                baseOffset: lineStart,
                extentOffset: lineEnd,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (editableTextState.mounted) {
                    editableTextState.showToolbar();
                  }
                });
              });
            },
          ),
        );
      }
    }

    // 複製
    if (!selection.isCollapsed &&
        selection.textInside(controller.text).isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: '複製',
          onPressed: () {
            Clipboard.setData(
                ClipboardData(text: selection.textInside(controller.text)));
            ContextMenuController.removeAny();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已複製到剪貼簿'),
                duration: Duration(milliseconds: 100),
              ),
            );
          },
        ),
      );
    }

    // 剪下
    if (!selection.isCollapsed &&
        selection.textInside(controller.text).isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: '剪下',
          onPressed: () {
            final selectedText = selection.textInside(controller.text);
            Clipboard.setData(ClipboardData(text: selectedText));

            final newText = controller.text.replaceRange(
              selection.start,
              selection.end,
              '',
            );
            controller.text = newText;
            controller.selection = TextSelection.collapsed(offset: selection.start);

            ContextMenuController.removeAny();
          },
        ),
      );
    }

    // 貼上
    buttonItems.add(
      ContextMenuButtonItem(
        label: '貼上',
        onPressed: () async {
          final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
          if (clipboardData?.text != null) {
            final text = clipboardData!.text!;
            final newText = controller.text.replaceRange(
              selection.start,
              selection.end,
              text,
            );
            controller.text = newText;
            controller.selection = TextSelection.collapsed(
              offset: selection.start + text.length,
            );

            ContextMenuController.removeAny();
          }
        },
      ),
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CaseMessageProvider>(context);
    final userProvider = Provider.of<UserProvider>(context);
    // 使用固定的測試 ID (101) 以匹配 fake data 中的派單者 ID
    // 實際整合 API 時改為: userProvider.user?.id ?? 101
    final currentUserId = 101;

    _isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              Text(
                widget.caseNumber,
                style: const TextStyle(fontSize: 16),
              ),
              const Text(
                '案件對話',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF469030),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Expanded(
              child: provider.isLoading && provider.currentCaseMessages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : provider.currentCaseMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.message,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                '暫無訊息',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          controller: _scrollController,
                          padding: const EdgeInsets.only(
                            top: 16,
                            bottom: 80,
                            left: 16,
                            right: 16,
                          ),
                          itemCount: provider.currentCaseMessages.length,
                          itemBuilder: (context, index) {
                            final message =
                                provider.currentCaseMessages[index];
                            return _buildMessageItem(
                                context, message, currentUserId);
                          },
                        ),
            ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(
      BuildContext context, CaseMessage message, int currentUserId) {
    final isUserMessage = message.isFromCurrentUser(currentUserId);

    return Align(
      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      key: ValueKey<int>(message.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUserMessage
              ? const Color(0xFF469030)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 發送者名稱
            if (!isUserMessage)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${message.senderNickName}（${message.senderName}）',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // 圖片消息
            if (message.messageType == 'image' && message.imageUrl != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildImageWidget(message.imageUrl!),
                  ),
                  if (message.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 16,
                          color:
                              isUserMessage ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                ],
              )
            else
              // 文字消息
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 16,
                  color: isUserMessage ? Colors.white : Colors.black87,
                ),
              ),

            const SizedBox(height: 4),

            // 時間
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                fontSize: 12,
                color: isUserMessage
                    ? Colors.white70
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl) {
    // 如果是本地檔案路徑
    if (imageUrl.startsWith('/')) {
      return Image.file(
        File(imageUrl),
        width: 200,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 150,
            color: Colors.grey.shade300,
            child: const Icon(Icons.broken_image, size: 48),
          );
        },
      );
    }

    // 網絡圖片
    return Image.network(
      imageUrl,
      width: 200,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: 200,
          height: 150,
          color: Colors.grey.shade300,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: 200,
          height: 150,
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image, size: 48),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding:
          EdgeInsets.fromLTRB(16, 8, 12, _isKeyboardVisible ? 8 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          // 圖片按鈕
          IconButton(
            icon: const Icon(Icons.image, color: Color(0xFF469030)),
            onPressed: _pickAndSendImage,
          ),

          const SizedBox(width: 8),

          // 文字輸入框
          Expanded(
            child: GestureDetector(
              onDoubleTap: () {
                if (_messageController.text.isNotEmpty) {
                  final cursorOffset = _messageController.selection.baseOffset;
                  final text = _messageController.text;

                  int lineStart = cursorOffset;
                  while (lineStart > 0 && text[lineStart - 1] != '\n') {
                    lineStart--;
                  }

                  int lineEnd = cursorOffset;
                  while (lineEnd < text.length && text[lineEnd] != '\n') {
                    lineEnd++;
                  }

                  _messageController.selection = TextSelection(
                    baseOffset: lineStart,
                    extentOffset: lineEnd,
                  );

                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (_currentEditableTextState != null &&
                        _currentEditableTextState!.mounted) {
                      _currentEditableTextState!.showToolbar();
                    }
                  });
                }
              },
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '輸入訊息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                contextMenuBuilder: (context, editableTextState) {
                  _currentEditableTextState = editableTextState;
                  return _buildContextMenu(
                      context, _currentEditableTextState!);
                },
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 發送按鈕
          Container(
            margin: const EdgeInsets.only(right: 4),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF469030),
              radius: 20,
              child: Transform.translate(
                offset: const Offset(1, 0),
                child: IconButton(
                  icon: const Icon(Icons.send),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  color: Colors.white,
                  onPressed: _sendMessage,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

