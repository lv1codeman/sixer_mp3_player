// lib/pages/file_browser_page.dart
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../widgets/sub_header.dart';
import '../widgets/highlighted_text.dart';
import '../utils/utils.dart';

import 'dart:io'; // 提供 Platform, Directory, File
import 'package:permission_handler/permission_handler.dart'; // 提供 Permission
import 'package:just_audio/just_audio.dart'; // 提供 AudioPlayer

class FileBrowserPage extends StatefulWidget {
  final List<Song> initialSongs;
  final Function(List<Song>) onScanComplete;
  final List<Song> currentQueue;
  final String? currentPath; // 接收目前播放中的路徑
  final String query;
  final String Function(Duration) format;
  final Set<String> favorites;
  final Function(String) onPlay;
  final Function(String) onToggleFav;
  final Function(List<Song>) onBatchAdd;
  final Function(bool, int, String) onSelectionChanged;

  const FileBrowserPage({
    super.key,
    required this.initialSongs,
    required this.onScanComplete,
    required this.currentQueue,
    required this.currentPath,
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

  bool _isScanning = false;
  final List<Song> _localSongs = []; // 建立內部的歌曲清單

  @override
  void initState() {
    super.initState();
    _localSongs.addAll(widget.initialSongs);
    if (_localSongs.isEmpty) {
      refreshFiles();
    }
  }

  // 原本的_checkPermissionAndScan，用於讀檔，只掃描手機上所有.mp3檔案並且排除/Android/資料夾
  Future<void> refreshFiles() async {
    bool hasPermission = false;
    if (Platform.isAndroid) {
      hasPermission =
          await Permission.audio.request().isGranted ||
          await Permission.storage.request().isGranted;
    }

    if (hasPermission) {
      setState(() {
        _isScanning = true;
        _localSongs.clear();
      });

      final root = Directory('/storage/emulated/0');
      final List<Song> tempSongs = [];

      try {
        await for (var entity
            in root.list(recursive: true, followLinks: false).handleError((e) {
              debugPrint("掃描路徑錯誤: $e"); // 避免空的 catch
            })) {
          if (entity is File &&
              entity.path.toLowerCase().endsWith('.mp3') &&
              !entity.path.contains('/Android/')) {
            //掃描時排除/Android/資料夾
            final player = AudioPlayer();
            Duration? d;
            try {
              d = await player.setFilePath(entity.path);
            } catch (e) {
              debugPrint("讀取時長出錯: $e");
            } finally {
              await player.dispose();
            }

            tempSongs.add(
              Song(
                path: entity.path,
                title: entity.path.split('/').last,
                duration: d ?? Duration.zero,
              ),
            );

            if (tempSongs.length % 20 == 0) {
              // 每20首掃描一次
              if (mounted) {
                setState(() {
                  _localSongs.clear();
                  _localSongs.addAll(tempSongs);
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint("掃描中斷: $e");
      }

      if (mounted) {
        setState(() {
          _localSongs.clear();
          _localSongs.addAll(tempSongs);
          _isScanning = false;
        });
        // 關鍵：將結果回傳給 MainScreen，讓 MainScreen 去執行 _saveData()
        widget.onScanComplete(_localSongs);
      }
    } else {
      myToast("未取得讀取權限");
    }
  }

  // 公開方法：讓 main.dart 可以透過 GlobalKey 呼叫來取消選取或執行加入
  void cancelSelection() {
    setState(() {
      _isMulti = false;
      _selected.clear();
    });
    widget.onSelectionChanged(false, 0, "00:00");
  }

  void performAdd() {
    final toAdd = _localSongs.where((s) {
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
    final selectedSongs = _localSongs.where((s) {
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

    final filtered = _localSongs.where((s) {
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
        if (_isScanning) const LinearProgressIndicator(),
        Expanded(
          child: _localSongs.isEmpty && !_isScanning
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
