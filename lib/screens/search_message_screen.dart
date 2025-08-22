import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../utils/api_config.dart';

class SearchMessageScreen extends StatefulWidget {
  const SearchMessageScreen({super.key});

  @override
  State<SearchMessageScreen> createState() => _SearchMessageScreenState();
}

class _SearchMessageScreenState extends State<SearchMessageScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Message> _searchResults = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入搜索關鍵字')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
    });

    try {
      final response = await ApiConfig.searchMessages(query);
      final List<dynamic> results = response['results'] ?? [];
      
      setState(() {
        _searchResults = results.map((json) => Message.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _searchResults = [];
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final dateFormat = DateFormat('MM/dd HH:mm');
    return dateFormat.format(dateTime.add(const Duration(hours: 8)));
  }

  // 自定義文字選擇選單
  Widget _buildContextMenu(BuildContext context, EditableTextState editableTextState) {
    final List<ContextMenuButtonItem> buttonItems = [];
    final TextEditingController controller = editableTextState.widget.controller!;
    final TextSelection selection = editableTextState.currentTextEditingValue.selection;

    // 只有在沒有選中文字時，才顯示"全選"按鈕
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
    }

    // 複製 (當有選中文字時)
    if (!selection.isCollapsed && selection.textInside(controller.text).isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: '複製',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: selection.textInside(controller.text)));
            ContextMenuController.removeAny();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已複製到剪貼簿'),
                duration: Duration(milliseconds: 200),
              ),
            );
          },
        ),
      );
    }

    // 剪下 (當有選中文字時)
    if (!selection.isCollapsed && selection.textInside(controller.text).isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: '剪下',
          onPressed: () {
            final selectedText = selection.textInside(controller.text);
            Clipboard.setData(ClipboardData(text: selectedText));
            
            // 刪除選中的文字
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

    // 貼上 (當剪貼簿有內容時)
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

  Widget _buildMessageItem(Message message) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  message.isFromServer ? Icons.support_agent : Icons.person,
                  size: 16,
                  color: message.isFromServer ? Colors.blue : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  message.isFromServer ? '系統' : '我',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: message.isFromServer ? Colors.blue : Colors.green,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDateTime(message.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                // 複製按鈕
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    // 顯示複製成功提示
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已複製訊息'),
                        duration: Duration(milliseconds: 200),
                      ),
                    );
                  },
                  child: const Icon(
                    Icons.copy,
                    size: 24,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message.content,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索訊息'),
        backgroundColor: const Color(0xFF469030),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '輸入搜索關鍵字...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _performSearch(),
                    contextMenuBuilder: (context, editableTextState) {
                      return _buildContextMenu(context, editableTextState);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _performSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF469030),
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('搜索'),
                ),
              ],
            ),
          ),
          
          // Results
          Expanded(
            child: _buildResultsSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (!_hasSearched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              '輸入關鍵字搜索過往訊息',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
                         const Text(
               '搜索失敗',
               style: TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.bold,
                 color: Colors.red,
               ),
             ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _performSearch,
              child: const Text('重試'),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              '沒有找到相關訊息',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildMessageItem(_searchResults[index]);
      },
    );
  }
} 