import 'package:flutter/material.dart';
import '../models/song.dart';
import '../widgets/sub_header.dart';
import '../widgets/highlights_text.dart';

class QueuePage extends StatelessWidget {
  final List<Song> queue;
  final String? currentPath;
  final String query; // 你原本用 query
  final String Function(Duration) format; // 你原本有傳入格式化函式
  final Function(String) onPlay;
  final VoidCallback onClear; // 你原本對應 _clearQueue
  final Function(int, int) onReorder;
  final Function(int) onDelete; // 你原本用 onDelete
  final VoidCallback onSaveAsPlaylist;

  const QueuePage({
    super.key,
    required this.queue,
    required this.currentPath,
    required this.query,
    required this.format,
    required this.onPlay,
    required this.onClear,
    required this.onReorder,
    required this.onDelete,
    required this.onSaveAsPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    // 根據你原本的邏輯過濾歌曲 (用 fileName 搜尋)
    final filtered = queue.where((s) {
      return s.fileName.toLowerCase().contains(query.toLowerCase());
    }).toList();

    // 計算總時長
    final totalDuration = filtered.fold(
      Duration.zero,
      (prev, s) => prev + s.duration,
    );

    return Column(
      children: [
        SubHeader(
          text: "佇列：${filtered.length} 首 (${format(totalDuration)})",
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 另存為播放清單按鈕
              if (filtered.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.playlist_add, size: 20),
                  onPressed: onSaveAsPlaylist,
                  tooltip: "另存為清音單",
                ),
              // 清空按鈕
              if (filtered.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep, size: 20),
                  onPressed: onClear,
                  tooltip: "清空佇列",
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text("佇列目前是空的", style: TextStyle(color: Colors.grey)),
                )
              : ReorderableListView.builder(
                  itemCount: filtered.length,
                  onReorder: onReorder,
                  itemBuilder: (ctx, idx) {
                    final song = filtered[idx];
                    final isPlaying = song.path == currentPath;

                    return ListTile(
                      key: ValueKey(song.path + idx.toString()),
                      leading: Icon(
                        isPlaying ? Icons.play_circle_fill : Icons.music_note,
                        color: isPlaying
                            ? Theme.of(context).primaryColor
                            : null,
                      ),
                      title: HighlightedText(
                        text: song.title,
                        query: query,
                        style: TextStyle(
                          fontWeight: isPlaying ? FontWeight.bold : null,
                          color: isPlaying
                              ? Theme.of(context).primaryColor
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        "${format(song.duration)} | ${song.path}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () =>
                            onDelete(idx), // 呼叫你原本的 _handleDeleteFromQueue
                      ),
                      onTap: () => onPlay(song.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
