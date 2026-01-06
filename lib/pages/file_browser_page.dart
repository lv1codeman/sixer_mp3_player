import 'package:flutter/material.dart';
import '../models/song.dart';
import '../widgets/sub_header.dart';
import '../widgets/highlighted_text.dart';
import '../utils/utils.dart';

// // 假設你有一個全域或工具類別的 toast，如果沒有，請換回 ScaffoldMessenger
// void myToast(String message) {
//   // 這裡放你原本的 toast 實作
// }

class FileBrowserPage extends StatefulWidget {
  final List<Song> allSongs;
  final List<Song> currentQueue;
  final String? currentPath; // 接收目前播放中的路徑
  final bool isScanning;
  final VoidCallback onScan;
  final String query;
  final String Function(Duration) format;
  final Set<String> favorites;
  final Function(String) onPlay;
  final Function(String) onToggleFav;
  final Function(List<Song>) onBatchAdd;
  final Function(bool, int, String) onSelectionChanged;

  const FileBrowserPage({
    super.key,
    required this.allSongs,
    required this.currentQueue,
    required this.currentPath,
    required this.isScanning,
    required this.onScan,
    required this.query,
    required this.format,
    required this.favorites,
    required this.onPlay,
    required this.onToggleFav,
    required this.onBatchAdd,
    required this.onSelectionChanged,
  });

  @override
  State<FileBrowserPage> createState() => FileBrowserPageState();
}

class FileBrowserPageState extends State<FileBrowserPage>
    with AutomaticKeepAliveClientMixin {
  final Set<String> _selected = {};
  List<String> get selectedPaths => _selected.toList();
  bool _isMulti = false;

  @override
  bool get wantKeepAlive => true;

  // 公開方法：讓 main.dart 可以透過 GlobalKey 呼叫來取消選取或執行加入
  void cancelSelection() {
    setState(() {
      _isMulti = false;
      _selected.clear();
    });
    widget.onSelectionChanged(false, 0, "00:00");
  }

  void performAdd() {
    final toAdd = widget.allSongs.where((s) {
      bool isSelected = _selected.contains(s.path);
      bool alreadyInQueue = widget.currentQueue.any(
        (item) => item.path == s.path,
      );
      return isSelected && !alreadyInQueue;
    }).toList();

    if (toAdd.isNotEmpty) {
      widget.onBatchAdd(toAdd);
      myToast("已加入 ${toAdd.length} 首新歌曲");
    } else {
      if (_selected.isNotEmpty) {
        myToast("選中的歌曲已全部在佇列中");
      }
    }
    cancelSelection();
  }

  void _notify() {
    final selectedSongs = widget.allSongs.where((s) {
      return _selected.contains(s.path);
    });
    final total = selectedSongs.fold(Duration.zero, (p, s) {
      return p + s.duration;
    });
    widget.onSelectionChanged(_isMulti, _selected.length, widget.format(total));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必須呼叫

    final filtered = widget.allSongs.where((s) {
      return s.fileName.toLowerCase().contains(widget.query.toLowerCase());
    }).toList();

    final totalDuration = filtered.fold(
      Duration.zero,
      (p, s) => p + s.duration,
    );

    return Column(
      children: [
        SubHeader(
          text: "本地音樂：${filtered.length} 首 (${widget.format(totalDuration)})",
        ),
        if (widget.isScanning) const LinearProgressIndicator(),
        Expanded(
          child: widget.allSongs.isEmpty && !widget.isScanning
              ? const Center(
                  child: Text(
                    "找不到音樂檔案(.mp3)",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final s = filtered[idx];
                    bool isChecked = _selected.contains(s.path);
                    bool isFav = widget.favorites.contains(s.path);
                    bool isPlaying = widget.currentPath == s.path;
                    return ListTile(
                      tileColor: isPlaying
                          ? Theme.of(context).primaryColor.withAlpha(30)
                          : null,
                      leading: _isMulti
                          ? Checkbox(
                              value: isChecked,
                              onChanged: (v) {
                                setState(() {
                                  if (v!) {
                                    _selected.add(s.path);
                                  } else {
                                    _selected.remove(s.path);
                                  }
                                });
                                _notify();
                              },
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.play_circle_fill
                                  : Icons.music_note,
                              color: isPlaying
                                  ? Theme.of(context).primaryColor
                                  : null,
                            ),
                      title: HighlightedText(
                        text: s.fileName,
                        query: widget.query,
                        // ✅ 新增：播放中加粗並變色
                        style: TextStyle(
                          fontWeight: isPlaying
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isPlaying
                              ? Theme.of(context).primaryColor
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        widget.format(s.duration),
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: _isMulti
                          ? null
                          : IconButton(
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: Colors.red,
                              ),
                              onPressed: () => widget.onToggleFav(s.path),
                            ),
                      onLongPress: () {
                        setState(() {
                          _isMulti = true;
                          _selected.add(s.path);
                        });
                        _notify();
                      },
                      onTap: () {
                        if (_isMulti) {
                          setState(() {
                            if (isChecked) {
                              _selected.remove(s.path);
                            } else {
                              _selected.add(s.path);
                            }
                          });
                          _notify();
                        } else {
                          widget.onPlay(s.path);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
