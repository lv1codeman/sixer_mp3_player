// lib/widgets/music_search_bar.dart
import 'package:flutter/material.dart';

class MusicSearchBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isSearching;
  final bool isBrowser; // 新增：判斷是否在瀏覽頁面
  final String title;
  final TextEditingController controller;
  final VoidCallback onSearchToggle;
  final VoidCallback onRefresh; // 新增：刷新回呼
  final VoidCallback onToggleTheme; // 新增：主題切換回呼
  final Function(String) onChanged;

  const MusicSearchBar({
    super.key,
    required this.isSearching,
    required this.isBrowser,
    required this.title,
    required this.controller,
    required this.onSearchToggle,
    required this.onRefresh,
    required this.onToggleTheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;

    return AppBar(
      title: isSearching
          ? TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜尋歌曲...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 18),
              onChanged: onChanged,
            )
          : Text(title),
      actions: [
        // 1. 刷新按鈕：僅在非搜尋且是瀏覽頁面時顯示
        if (!isSearching && isBrowser) ...{
          IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
        },

        // 2. 搜尋/關閉按鈕切換
        IconButton(
          icon: Icon(isSearching ? Icons.close : Icons.search),
          onPressed: () {
            if (isSearching) {
              controller.clear();
              onChanged(''); // 清除過濾
            }
            onSearchToggle();
          },
        ),

        // 3. 主題切換按鈕
        IconButton(
          icon: Icon(
            brightness == Brightness.light ? Icons.dark_mode : Icons.light_mode,
          ),
          onPressed: onToggleTheme,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
