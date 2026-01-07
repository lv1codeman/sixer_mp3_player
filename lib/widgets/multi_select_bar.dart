// lib/widgets/multi_select_bar.dart
import 'package:flutter/material.dart';

class MultiSelectActionBar extends StatelessWidget {
  final int selectedCount;
  final String selectedTotalTime;
  final VoidCallback onAdd; // 加入佇列
  final VoidCallback onSaveAsPlaylist; // 另存清單
  final VoidCallback onCancel; // 取消選擇

  const MultiSelectActionBar({
    super.key,
    required this.selectedCount,
    required this.selectedTotalTime,
    required this.onAdd,
    required this.onSaveAsPlaylist,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      // 設定與 MiniPlayer 相似的邊距，保持視覺一致
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        // 加上一點陰影讓它與上方的列表有區隔
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：狀態顯示
          Row(
            children: [
              Icon(Icons.check_circle, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                "已選 $selectedCount 首",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "($selectedTotalTime)",
                style: TextStyle(color: colorScheme.secondary, fontSize: 14),
              ),
              const Spacer(),
              // 右側放一個快速取消的小按鈕
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onCancel,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 第二行：按鈕組
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.queue_music),
                  label: const Text("加入佇列"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSaveAsPlaylist,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text("另存清單"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
