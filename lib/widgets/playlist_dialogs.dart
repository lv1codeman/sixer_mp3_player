import 'package:flutter/material.dart';

/// 顯示「將歌曲存入播放清單」的對話框 - 互斥邏輯版
Future<void> showSaveSongsToPlaylistDialog({
  required BuildContext context,
  required List<String> paths,
  required Map<String, List<String>> playlists,
  required Function(String, List<String>) onSave,
}) async {
  final TextEditingController nameController = TextEditingController();
  String? selectedPlaylist;

  return showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          // 判斷邏輯
          final bool isInputNotEmpty = nameController.text.trim().isNotEmpty;
          final bool isDropdownSelected = selectedPlaylist != null;

          // 互斥狀態：如果輸入框有字，就禁用下拉選單；反之亦然
          final bool disableDropdown = isInputNotEmpty;
          final bool disableInput = isDropdownSelected;

          return AlertDialog(
            title: const Text("另存為播放清單"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 新建清單區塊
                const Text("建立新清單：", style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  enabled: !disableInput, // 互斥禁用
                  onChanged: (value) {
                    // 當文字改變時，需要重新觸發 UI 重繪以禁用/啟用下拉選單
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: "新名稱",
                    isDense: true,
                    filled: disableInput,
                    fillColor: Colors.grey.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 10),

                // 2. 加入現有清單區塊
                const Text("加入現有清單：", style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                if (playlists.isEmpty)
                  const Text("目前無現有清單", style: TextStyle(color: Colors.grey))
                else
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedPlaylist,
                    hint: const Text("選擇現有清單"),
                    disabledHint: const Text("已輸入新名稱"),
                    // 互斥邏輯：如果輸入框有字，onChanged 設為 null 即為禁用
                    onChanged: disableDropdown
                        ? null
                        : (String? newValue) {
                            setDialogState(() {
                              selectedPlaylist = newValue;
                            });
                          },
                    items: playlists.keys.map((String name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                  ),
                if (isDropdownSelected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextButton(
                      onPressed: () {
                        setDialogState(() {
                          selectedPlaylist = null;
                        });
                      },
                      child: const Text("清除選擇"),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("取消"),
              ),
              // 確定按鈕：只有當兩者之一有值時才啟用
              ElevatedButton(
                onPressed: (isInputNotEmpty || isDropdownSelected)
                    ? () {
                        final finalName = isInputNotEmpty
                            ? nameController.text.trim()
                            : selectedPlaylist!;
                        onSave(finalName, paths);
                        Navigator.pop(context);
                      }
                    : null, // 兩者都空時禁用
                child: const Text("確定"),
              ),
            ],
          );
        },
      );
    },
  );
}
