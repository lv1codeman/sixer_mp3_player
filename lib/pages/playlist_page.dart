import 'package:flutter/material.dart';
import '../widgets/sub_header.dart';
import '../widgets/highlighted_text.dart';
import '../utils/utils.dart';
import '../utils/logger.dart';
// --- 4. 清單頁面 ---

class PlaylistPage extends StatefulWidget {
  final Map<String, List<String>> playlists;
  final String query;
  final Function(String) onPlaylistTap;
  // final Function(String) onDeletePlaylist;
  final VoidCallback onDataChanged;

  const PlaylistPage({
    super.key,
    required this.playlists,
    required this.query,
    required this.onPlaylistTap,
    // required this.onDeletePlaylist,
    required this.onDataChanged,
  });

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  @override
  Widget build(BuildContext context) {
    // 3. 根據 query 過濾清單名稱
    final names = widget.playlists.keys.where((name) {
      return name.toLowerCase().contains(widget.query.toLowerCase());
    }).toList();

    return Column(
      children: [
        // 加入一個簡單的數量統計（與其他頁面風格一致）
        SubHeader(
          text: (widget.query == '')
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
                title: HighlightedText(text: name, query: widget.query),
                subtitle: Text("共 ${widget.playlists[name]!.length} 首歌曲"),
                onTap: () {
                  widget.onPlaylistTap(name);
                },
                onLongPress: () {
                  Logger.d('長按清單項目: $name');
                  //對話框需要有特定輸入，不能直接用myConfirmDialog
                  showRenameDialog(context, name);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    myConfirmDialog(
                      title: "刪除播放清單",
                      content: "確定要刪除播放清單「$name」嗎？這動作無法復原。",
                      onConfirm: () {
                        widget.playlists.remove(name);
                        widget.onDataChanged();
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

  Future showRenameDialog(BuildContext context, String oldName) async {
    Logger.d('showRenameDialog for: $oldName');

    // 預填原本的名稱
    final TextEditingController nameController = TextEditingController(
      text: oldName,
    );
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("播放清單名稱更改"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("請輸入新的清單名稱"),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: "新建清單名稱",
                  hintText: "請輸入新名稱",
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text("取消"),
              onPressed: () => Navigator.of(context).pop(), // 關閉對話框
            ),
            TextButton(
              child: Text("確定"),
              onPressed: () {
                setState(() {
                  String newName = nameController.text.trim();
                  // 1. 直接在 Page 內處理業務邏輯（這就是你想要的）
                  final List<String> songs = widget.playlists[oldName] ?? [];
                  widget.playlists[newName] = List.from(songs);
                  widget.playlists.remove(oldName);
                });
                // String newName = nameController.text.trim();

                // // 檢查：名稱不能為空，且不能與其他清單重複
                // if (newName.isEmpty) {
                //   myToast("名稱不能為空");
                //   return;
                // }
                // if (widget.playlists.containsKey(newName) &&
                //     newName != oldName) {
                //   myToast("清單名稱已存在");
                //   return;
                // }

                // Logger.i("準備更名：$oldName -> $newName");
                // // 執行重命名邏輯

                // if (oldName != newName) {
                //   setState(() {
                //     // 這行會觸發 main.dart 裡面的 playlists 更新
                //     widget.onRename(oldName, newName);
                //   });
                // }
                Navigator.of(context).pop(true);
                widget.onDataChanged();
                myToast("更名成功");
              },
            ),
          ],
        );
      },
    );
  }
}
