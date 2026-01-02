import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiotags/audiotags.dart';

void main() {
  runApp(const SixerMP3Player());
}

Widget _buildSubHeader({required String text, Widget? trailing}) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.black12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: const TextStyle(fontSize: 12)),
          if (trailing != null) trailing,
        ],
      ),
    ),
  );
}

// --- 歌曲資料模型 ---
class Song {
  final String path;
  final Duration duration;
  Song({required this.path, required this.duration});

  String get fileName {
    return path.split('/').last;
  }
}

class SixerMP3Player extends StatefulWidget {
  const SixerMP3Player({super.key});

  @override
  State<SixerMP3Player> createState() => _SixerMP3PlayerState();
}

class _SixerMP3PlayerState extends State<SixerMP3Player> {
  // 建立一個變數來儲存主題狀態
  ThemeMode _themeMode = ThemeMode.system;

  // 切換主題的方法
  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SixerMP3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode, // 使用動態的 _themeMode
      // 將切換功能傳遞給 MainScreen
      home: MainScreen(onToggleTheme: _toggleTheme),
    );
  }
}

// --- 搜尋高亮顯示組件 ---
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final List<TextSpan> spans = [];
    final String lowercaseText = text.toLowerCase();
    final String lowercaseQuery = query.toLowerCase();
    int start = 0;
    int index = lowercaseText.indexOf(lowercaseQuery);

    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0x33FF9800),
          ),
        ),
      );
      start = index + query.length;
      index = lowercaseText.indexOf(lowercaseQuery, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class MainScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const MainScreen({super.key, required this.onToggleTheme});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<_FileBrowserPageState> _fileBrowserKey = GlobalKey();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<Song> _playQueue = [];
  String _currentPath = "";
  String _currentTitle = "未在播放";
  bool _isPlaying = false;
  int _playMode = 0; // 0: 列表, 1: 單曲, 2: 隨機

  final Set<String> _favorites = {};
  final Map<String, List<String>> _playlists = {};

  bool _isMultiSelectMode = false;
  int _selectedCount = 0;
  String _selectedTotalTime = "00:00";
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initAudioListeners();
  }

  void _initAudioListeners() {
    _audioPlayer.onDurationChanged.listen((d) {
      setState(() {
        _duration = d;
      });
    });
    _audioPlayer.onPositionChanged.listen((p) {
      setState(() {
        _position = p;
      });
    });
    _audioPlayer.onPlayerStateChanged.listen((s) {
      setState(() {
        _isPlaying = (s == PlayerState.playing);
      });
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      if (_playMode == 1) {
        _audioPlayer.resume();
      } else {
        _handleNext();
      }
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) {
      return n.toString().padLeft(2, "0");
    }

    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
    }
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  void _handlePrevious() {
    if (_playQueue.isEmpty) {
      return;
    }
    int idx = _playQueue.indexWhere((s) {
      return s.path == _currentPath;
    });
    int prevIdx = (idx - 1 + _playQueue.length) % _playQueue.length;
    _handlePlay(_playQueue[prevIdx].path);
  }

  void _handleNext() {
    if (_playQueue.isEmpty) {
      return;
    }
    int idx = _playQueue.indexWhere((s) {
      return s.path == _currentPath;
    });
    int nextIdx;
    if (_playMode == 2) {
      nextIdx = Random().nextInt(_playQueue.length);
    } else {
      nextIdx = (idx + 1) % _playQueue.length;
    }
    _handlePlay(_playQueue[nextIdx].path);
  }

  void _handlePlay(String path) async {
    await _audioPlayer.stop();
    try {
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() {
        _currentPath = path;
        _currentTitle = path.split('/').last;
      });
    } catch (e) {
      debugPrint("播放失敗: $e");
    }
  }

  // 順序調整邏輯
  void _handleReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final Song item = _playQueue.removeAt(oldIndex);
      _playQueue.insert(newIndex, item);
    });
  }

  // 刪除單曲邏輯
  void _handleDeleteFromQueue(int index) {
    setState(() {
      _playQueue.removeAt(index);
      // 如果刪除的是正在播放的，可以自行決定是否停止
    });
  }

  void _clearQueue() {
    setState(() {
      _playQueue.clear();
      // 這裡可以選擇是否要同時停止播放，如果要停止則加上：
      _audioPlayer.stop();
      _currentPath = "";
      _currentTitle = "未在播放";
    });
  }

  void _deletePlaylist(String name) {
    setState(() {
      _playlists.remove(name);
    });
    _saveData(); // 確保刪除後同步到本機儲存
  }

  void _addPlaylistToQueue(String playlistName) {
    final paths = _playlists[playlistName];
    if (paths != null) {
      setState(() {
        for (var path in paths) {
          bool alreadyIn = _playQueue.any((s) {
            return s.path == path;
          });
          if (!alreadyIn) {
            _playQueue.add(Song(path: path, duration: Duration.zero));
          }
        }
        _selectedIndex = 0; // 跳轉到佇列頁面
      });
    }
  }

  // 整合後的通用方法：傳入要儲存的歌曲路徑清單
  void _showSaveSongsToPlaylistDialog(List<String> songPaths) {
    if (songPaths.isEmpty) return;

    final TextEditingController nameController = TextEditingController();
    String? selectedExistingName;
    bool isDropdownActive = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 如果下拉選單有值，禁用輸入框；反之亦然
            bool isTextEnabled = !isDropdownActive;
            bool isDropdownEnabled = nameController.text.trim().isEmpty;

            return AlertDialog(
              title: const Text("儲存至播放清單"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: isTextEnabled,
                    decoration: const InputDecoration(
                      labelText: "新建清單名稱",
                      hintText: "請輸入名稱",
                    ),
                    onChanged: (v) => setDialogState(() {}),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      "— 或 —",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "加入現有清單"),
                    hint: const Text("選擇已有清單"),
                    onChanged: isDropdownEnabled
                        ? (val) {
                            setDialogState(() {
                              selectedExistingName = val;
                              isDropdownActive = (val != null);
                            });
                          }
                        : null,
                    items: _playlists.keys.map((n) {
                      return DropdownMenuItem(value: n, child: Text(n));
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("取消"),
                ),
                TextButton(
                  onPressed: () {
                    String finalName = isDropdownActive
                        ? (selectedExistingName ?? "")
                        : nameController.text.trim();

                    if (finalName.isNotEmpty) {
                      setState(() {
                        if (!_playlists.containsKey(finalName)) {
                          _playlists[finalName] = [];
                        }
                        // 整合邏輯：將傳入的所有路徑加入該清單
                        _playlists[finalName]!.addAll(songPaths);
                        // 去除重複歌曲（選選）
                        _playlists[finalName] = _playlists[finalName]!
                            .toSet()
                            .toList();
                      });
                      _saveData();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("已加入清單：$finalName")),
                      );
                    }
                  },
                  child: const Text("儲存"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleFav(String path) {
    if (path.isEmpty) {
      return;
    }
    setState(() {
      if (_favorites.contains(path)) {
        _favorites.remove(path);
      } else {
        _favorites.add(path);
      }
    });
    _saveData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final String? favJson = prefs.getString('fav');
      if (favJson != null) {
        _favorites.addAll(jsonDecode(favJson).cast<String>());
      }
      final String? listJson = prefs.getString('list');
      if (listJson != null) {
        Map<String, dynamic> listMap = jsonDecode(listJson);
        listMap.forEach((k, v) {
          _playlists[k] = (v as List).cast<String>();
        });
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fav', jsonEncode(_favorites.toList()));
    await prefs.setString('list', jsonEncode(_playlists));
  }

  // 頁面指示器
  Widget _buildTopIndicatorBar(BuildContext context, int currentIndex) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 3, // 指示線的高度
      child: Row(
        children: List.generate(4, (i) {
          return Expanded(
            child: Container(
              // horizontal 的數值決定線條的長度，越大線條越短
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                // 只有選中的索引才顯示顏色，其餘透明
                color: i == currentIndex
                    ? colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    bool isBrowser = (_selectedIndex == 1);
    bool isPlaylistPage = (_selectedIndex == 3);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true, // 自動彈起鍵盤
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  hintText: "搜尋音樂...",
                  border: InputBorder.none, // 移除輸入框底線，使其融入 AppBar
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                onChanged: (v) {
                  setState(() {}); // 即時更新列表過濾
                },
              )
            : const Text("SixerMP3"),
        actions: [
          // 2. 根據是否搜尋中，切換按鈕圖示與功能
          _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear(); // 清除搜尋內容
                    });
                  },
                )
              : IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      _searchController.clear();
                    });
                  },
                ),
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.light
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            onPressed: widget.onToggleTheme, // 呼叫傳進來的切換函數
          ),
          if (!_isSearching && isBrowser) ...{
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _fileBrowserKey.currentState?._checkPermissionAndScan();
              },
            ),
          },
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                QueuePage(
                  queue: _playQueue,
                  currentPath: _currentPath,
                  query: _searchController.text,
                  format: _formatDuration,
                  onPlay: _handlePlay,
                  onClear: _clearQueue,
                  onReorder: _handleReorder, // 傳入排序
                  onDelete: _handleDeleteFromQueue, // 傳入刪除
                  onSaveAsPlaylist: () {
                    // 傳入目前過濾後（或全部）的佇列歌曲路徑
                    final filteredPaths = _playQueue
                        .where(
                          (s) => s.fileName.toLowerCase().contains(
                            _searchController.text.toLowerCase(),
                          ),
                        )
                        .map((s) => s.path)
                        .toList();
                    _showSaveSongsToPlaylistDialog(filteredPaths);
                  }, // 傳入另存
                ),
                FileBrowserPage(
                  key: _fileBrowserKey,
                  query: _searchController.text,
                  format: _formatDuration,
                  favorites: _favorites,
                  onPlay: _handlePlay,
                  onToggleFav: _toggleFav,
                  onBatchAdd: (songs) {
                    setState(() {
                      _playQueue.addAll(songs);
                    });
                  },
                  onSelectionChanged: (mode, count, time) {
                    setState(() {
                      _isMultiSelectMode = mode;
                      _selectedCount = count;
                      _selectedTotalTime = time;
                    });
                  },
                ),
                FavoritePage(
                  favorites: _favorites,
                  query: _searchController.text,
                  format: _formatDuration,
                  onPlay: _handlePlay,
                  onToggle: _toggleFav,
                ),
                PlaylistPage(
                  playlists: _playlists,
                  query: _searchController.text,
                  onPlaylistTap: _addPlaylistToQueue,
                  onDeletePlaylist: _deletePlaylist,
                ),
              ],
            ),
          ),

          const Divider(height: 1),
          if (!isPlaylistPage) ...{
            _isMultiSelectMode
                ? Container(
                    // 多選操作區
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: colorScheme.primaryContainer,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 第一列：顯示資訊
                        Row(
                          children: [
                            const Icon(Icons.check_circle),
                            const SizedBox(width: 8),
                            Text(
                              "已選 $_selectedCount 首",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "($_selectedTotalTime)",
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 第二列：操作按鈕
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 1. 加入佇列
                            ElevatedButton.icon(
                              onPressed: () {
                                _fileBrowserKey.currentState?._performAdd();
                              },
                              icon: const Icon(Icons.queue_music),
                              label: const Text("加入佇列"),
                            ),
                            // 2. 另存播放清單
                            ElevatedButton.icon(
                              onPressed: () {
                                final paths =
                                    _fileBrowserKey
                                        .currentState
                                        ?.selectedPaths ??
                                    [];
                                if (paths.isNotEmpty) {
                                  _showSaveSongsToPlaylistDialog(paths);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("請先選擇歌曲")),
                                  );
                                }
                              },
                              icon: const Icon(Icons.playlist_add),
                              label: const Text("另存清單"),
                            ),
                            // 3. 取消按鈕
                            TextButton.icon(
                              onPressed: () {
                                _fileBrowserKey.currentState
                                    ?._cancelSelection();
                              },
                              icon: const Icon(Icons.close),
                              label: const Text("取消"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Container(
                    // 單點：播放音樂
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // 播放進度條
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            children: [
                              // 左側：當前播放時間
                              Text(
                                _formatDuration(_position),
                                style: const TextStyle(fontSize: 12),
                              ),
                              // 中間：進度條，使用 Expanded 填滿空間
                              Expanded(
                                child: Slider(
                                  value: _position.inSeconds.toDouble(),
                                  max: _duration.inSeconds.toDouble() > 0
                                      ? _duration.inSeconds.toDouble()
                                      : 1.0,
                                  onChanged: (v) {
                                    _audioPlayer.seek(
                                      Duration(seconds: v.toInt()),
                                    );
                                  },
                                ),
                              ),
                              // 右側：總時長
                              Text(
                                _formatDuration(_duration),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: Icon(
                                _favorites.contains(_currentPath)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                _toggleFav(_currentPath);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              onPressed: isBrowser ? null : _handlePrevious,
                            ),
                            IconButton(
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                              ),
                              iconSize: 42,
                              color: colorScheme.primary,
                              onPressed: () {
                                if (_isPlaying) {
                                  _audioPlayer.pause();
                                } else {
                                  _audioPlayer.resume();
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              onPressed: isBrowser ? null : _handleNext,
                            ),
                            IconButton(
                              icon: Icon(
                                _playMode == 0
                                    ? Icons.repeat
                                    : (_playMode == 1
                                          ? Icons.repeat_one
                                          : Icons.shuffle),
                              ),
                              onPressed: () {
                                setState(() {
                                  _playMode = (_playMode + 1) % 3;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          },
          if (!isPlaylistPage) const Divider(height: 1),
        ],
      ),

      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min, // 關鍵：確保不佔用多餘空間
        children: [
          // 1. 放置指示條
          _buildTopIndicatorBar(context, _selectedIndex),

          // 2. 原本的 BottomNavigationBar
          BottomNavigationBar(
            currentIndex: _selectedIndex,
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0, // 設為 0 讓它跟上面的指示條貼合
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.6), // 使用新的 withValues 語法
            type: BottomNavigationBarType.fixed,
            onTap: (i) {
              if (_isMultiSelectMode) {
                _fileBrowserKey.currentState?._cancelSelection();
              }
              setState(() {
                _selectedIndex = i;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.queue_music),
                label: '佇列',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder_open),
                label: '瀏覽',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.favorite), label: '收藏'),
              BottomNavigationBarItem(
                icon: Icon(Icons.playlist_play),
                label: '清單',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- 1. 佇列頁面 ---
class QueuePage extends StatelessWidget {
  final List<Song> queue;
  final String currentPath;
  final String query;
  final String Function(Duration) format;
  final Function(String) onPlay;
  final VoidCallback onClear;
  final Function(int, int) onReorder;
  final Function(int) onDelete;
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
    final filtered = queue.where((s) {
      return s.fileName.toLowerCase().contains(query.toLowerCase());
    }).toList();

    final totalDuration = filtered.fold(
      Duration.zero,
      (p, s) => p + s.duration,
    );

    return Column(
      children: [
        _buildSubHeader(
          text: "佇列：${filtered.length} 首 (${format(totalDuration)})",
          trailing: filtered.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 新增：加入清單鈕 (在左邊)
                    TextButton.icon(
                      onPressed: onSaveAsPlaylist,
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text("加入清單", style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    // 原本的清空鈕 (在右邊)
                    TextButton.icon(
                      onPressed: onClear,
                      icon: const Icon(
                        Icons.delete_sweep,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        "清空",
                        style: TextStyle(fontSize: 12, color: Colors.redAccent),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                )
              : null,
        ),

        Expanded(
          child: ReorderableListView.builder(
            // 當搜尋關鍵字不為空時，通常建議禁用排序以防索引混亂，這裡由外部邏輯處理
            onReorder: (oldIdx, newIdx) {
              // 找到原始 queue 中的真實索引進行調整
              final int realOldIdx = queue.indexOf(filtered[oldIdx]);
              int realNewIdx = queue.indexOf(
                filtered[newIdx > oldIdx ? newIdx - 1 : newIdx],
              );
              if (newIdx > oldIdx) realNewIdx++;
              onReorder(realOldIdx, realNewIdx);
            },
            buildDefaultDragHandles: false, // 自定義漢堡條
            itemCount: filtered.length,
            itemBuilder: (ctx, idx) {
              final s = filtered[idx];
              // 為了防止重複歌曲在排序時報錯，Key 必須唯一
              final itemKey = ValueKey("${s.path}_$idx");

              return ListTile(
                key: itemKey,
                selected: (s.path == currentPath),
                // 最左邊：漢堡條 (ReorderableDelayedDragStartListener 實作長按拖拉)
                leading: ReorderableDelayedDragStartListener(
                  index: idx,
                  child: const Icon(Icons.menu),
                ),
                title: HighlightedText(text: s.fileName, query: query),
                subtitle: Text(
                  format(s.duration),
                  style: const TextStyle(fontSize: 10),
                ),
                // 最右邊：刪除 icon
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _showDeleteConfirm(context, s),
                ),
                onTap: () => onPlay(s.path),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirm(BuildContext context, Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("確認刪除"),
        content: Text("確定要從佇列中移除「${song.fileName}」嗎？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              // 找到原始索引並刪除
              onDelete(queue.indexOf(song));
              Navigator.pop(ctx);
            },
            child: const Text("確認", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// --- 2. 瀏覽頁面 ---
class FileBrowserPage extends StatefulWidget {
  final String query;
  final String Function(Duration) format;
  final Set<String> favorites;
  final Function(String) onPlay;
  final Function(String) onToggleFav;
  final Function(List<Song>) onBatchAdd;
  final Function(bool, int, String) onSelectionChanged;

  const FileBrowserPage({
    super.key,
    required this.query,
    required this.format,
    required this.favorites,
    required this.onPlay,
    required this.onToggleFav,
    required this.onBatchAdd,
    required this.onSelectionChanged,
  });

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  final List<Song> _allSongs = []; // 欄位設為 final
  final Set<String> _selected = {};
  List<String> get selectedPaths => _selected.toList();
  bool _isMulti = false;
  bool _isScanning = false;

  void _cancelSelection() {
    setState(() {
      _isMulti = false;
      _selected.clear();
    });
    widget.onSelectionChanged(false, 0, "00:00");
  }

  void _performAdd() {
    final toAdd = _allSongs.where((s) {
      return _selected.contains(s.path);
    }).toList();
    widget.onBatchAdd(toAdd);
    _cancelSelection();
  }

  Future<void> _checkPermissionAndScan() async {
    if (await Permission.audio.request().isGranted ||
        await Permission.storage.request().isGranted) {
      setState(() {
        _isScanning = true;
        _allSongs.clear();
      });

      final root = Directory('/storage/emulated/0');
      try {
        await for (var entity
            in root.list(recursive: true, followLinks: false).handleError((e) {
              // 靜默處理權限不足的目錄
            })) {
          if (entity is File &&
              entity.path.toLowerCase().endsWith('.mp3') &&
              !entity.path.contains('/Android/')) {
            Duration d = Duration.zero;
            try {
              final tag = await AudioTags.read(
                entity.path,
              ).timeout(const Duration(milliseconds: 500));
              if (tag != null && tag.duration != null) {
                d = Duration(seconds: tag.duration!);
              }
            } catch (e) {
              // 標籤讀取失敗時保留 Duration.zero
            }

            if (mounted) {
              setState(() {
                _allSongs.add(Song(path: entity.path, duration: d));
              });
            }
          }
        }
      } catch (e) {
        // 捕捉掃描中斷
      }
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allSongs.where((s) {
      return s.fileName.toLowerCase().contains(widget.query.toLowerCase());
    }).toList();
    final totalDuration = filtered.fold(Duration.zero, (p, s) {
      return p + s.duration;
    });

    return Column(
      children: [
        _buildSubHeader(
          text: "本地音樂：${filtered.length} 首 (${widget.format(totalDuration)})",
          // 如果未來想在這裡加按鈕（例如全選），可以放在 trailing 參數
        ),
        // 如果正在掃描，顯示進度條
        if (_isScanning) const LinearProgressIndicator(),
        Expanded(
          child: _allSongs.isEmpty && !_isScanning
              ? Center(
                  child: ElevatedButton(
                    onPressed: _checkPermissionAndScan,
                    child: const Text("掃描檔案"),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final s = filtered[idx];
                    bool isChecked = _selected.contains(s.path);
                    bool isFav = widget.favorites.contains(s.path);

                    return ListTile(
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
                          : const Icon(Icons.music_note),
                      title: HighlightedText(
                        text: s.fileName,
                        query: widget.query,
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
                              onPressed: () {
                                widget.onToggleFav(s.path);
                              },
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

  void _notify() {
    final selectedSongs = _allSongs.where((s) {
      return _selected.contains(s.path);
    });
    final total = selectedSongs.fold(Duration.zero, (p, s) {
      return p + s.duration;
    });
    widget.onSelectionChanged(_isMulti, _selected.length, widget.format(total));
  }
}

// --- 3. 收藏頁面 ---
class FavoritePage extends StatelessWidget {
  final Set<String> favorites;
  final String query;
  final String Function(Duration) format;
  final Function(String) onPlay;
  final Function(String) onToggle;

  const FavoritePage({
    super.key,
    required this.favorites,
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
        _buildSubHeader(text: "收藏歌曲：${list.length} 首"),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (ctx, idx) {
              final path = list[idx];
              return ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: HighlightedText(
                  text: path.split('/').last,
                  query: query,
                ),
                onTap: () {
                  onPlay(path);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    onToggle(path);
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
        _buildSubHeader(
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
                    onDeletePlaylist(name);
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
