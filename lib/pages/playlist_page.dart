import 'package:flutter/material.dart';
import '../widgets/sub_header.dart';
import '../widgets/highlighted_text.dart';
import '../utils/utils.dart';
// --- 4. 清單頁面 ---

class PlaylistPage extends StatelessWidget {
  final Map<String, List<String>> playlists;
  final String query;
  final Function(String) onPlaylistTap;
  final Function(String) onDeletePlaylist;

  const PlaylistPage({
    super.key,
    required this.playlists,
    required this.query,
    required this.onPlaylistTap,
    required this.onDeletePlaylist,
  });

  @override
  Widget build(BuildContext context) {
    // 3. 根據 query 過濾清單名稱
    final names = playlists.keys.where((name) {
      return name.toLowerCase().contains(query.toLowerCase());
    }).toList();

    return Column(
      children: [
        // 加入一個簡單的數量統計（與其他頁面風格一致）
        SubHeader(
          text: (query == '')
              ? "現有清單：${names.length} 個"
              : "符合條件的清單：${names.length} 個",
        ),
        Expanded(
          child: ListView.builder(
            itemCount: names.length,
            itemBuilder: (ctx, idx) {
              final name = names[idx];
              return ListTile(
                leading: const Icon(Icons.playlist_play),
                // 4. 使用之前定義的 HighlightedText 讓搜尋結果更直觀
                title: HighlightedText(text: name, query: query),
                subtitle: Text("共 ${playlists[name]!.length} 首歌曲"),
                onTap: () {
                  onPlaylistTap(name);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    myConfirmDialog(
                      title: "刪除播放清單",
                      content: "確定要刪除播放清單「$name」嗎？這動作無法復原。",
                      onConfirm: () {
                        onDeletePlaylist(name);
                        myToast("播放清單「$name」已刪除", durationSeconds: 1.5);
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
