import 'package:flutter/material.dart';
import '../widgets/sub_header.dart';
import '../widgets/highlighted_text.dart';
import '../utils/utils.dart';

// --- 3. 收藏頁面 ---
class FavoritePage extends StatelessWidget {
  final Set<String> favorites;
  final String? currentPath; // 接收目前播放中的路徑
  final String query;
  final String Function(Duration) format;
  final Function(String) onPlay;
  final Function(String) onToggle;

  const FavoritePage({
    super.key,
    required this.favorites,
    required this.currentPath,
    required this.query,
    required this.format,
    required this.onPlay,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final list = favorites.where((p) {
      return p.split('/').last.toLowerCase().contains(query.toLowerCase());
    }).toList();

    return Column(
      children: [
        SubHeader(text: "收藏歌曲：${list.length} 首"),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (ctx, idx) {
              final path = list[idx];
              final bool isPlaying = path == currentPath;
              return ListTile(
                tileColor: isPlaying
                    ? Theme.of(context).primaryColor.withAlpha(30)
                    : null,
                leading: Icon(
                  isPlaying ? Icons.play_circle_fill : Icons.favorite,
                  color: isPlaying
                      ? Theme.of(context).primaryColor
                      : Colors.red,
                ),
                title: HighlightedText(
                  text: path.split('/').last,
                  query: query,
                  // ✅ 播放中標題加粗且變色
                  style: TextStyle(
                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                    color: isPlaying ? Theme.of(context).primaryColor : null,
                  ),
                ),
                onTap: () {
                  onPlay(path);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    myConfirmDialog(
                      title: "取消收藏",
                      content: "確定要將「${path.split('/').last}」從收藏中移除嗎？",
                      onConfirm: () {
                        onToggle(path);
                        // 執行原本的刪除邏輯
                        myToast("已移除收藏", durationSeconds: 1.0);
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
