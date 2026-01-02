import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const SixerMP3Player());

class SixerMP3Player extends StatelessWidget {
  const SixerMP3Player({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sixer MP3 Player',
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
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

// --- 自定義組件：跑馬燈文字 ---
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final bool isScroll;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.isScroll = false,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    if (widget.isScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
    }
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果從不捲動變為要捲動，則啟動動畫
    if (widget.isScroll && !oldWidget.isScroll) {
      _startScrolling();
    }
    // 如果停止捲動，則回到起點
    else if (!widget.isScroll && oldWidget.isScroll) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  void _startScrolling() async {
    while (mounted && widget.isScroll && _scrollController.hasClients) {
      await Future.delayed(const Duration(seconds: 1)); // 起點停頓
      if (!_scrollController.hasClients || !widget.isScroll) break;

      double maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        // 開始捲動
        await _scrollController.animateTo(
          maxScroll,
          duration: Duration(milliseconds: (maxScroll * 40).toInt()),
          curve: Curves.linear,
        );

        await Future.delayed(const Duration(seconds: 2)); // 終點停頓

        if (mounted && _scrollController.hasClients) {
          // 快速回到起點
          await _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
          );
        }
      } else {
        break; // 不需要捲動
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (widget.style?.fontSize ?? 14) * 1.8,
      child: ListView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Text(widget.text, style: widget.style, maxLines: 1),
          // 只有在捲動時才在後方留白，避免短檔名也出現空白
          if (widget.isScroll) const SizedBox(width: 50),
        ],
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  bool _isDarkMode = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<_FileBrowserPageState> _fileBrowserKey = GlobalKey();

  // 播放器狀態
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<FileSystemEntity> _playQueue = [];
  String _currentTitle = "未在播放";
  String _currentPath = "";
  bool _isPlaying = false;
  int _playMode = 0;

  // 多選狀態
  bool _isMultiSelectMode = false;
  int _selectedCount = 0;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSub, _positionSub, _stateSub, _completeSub;

  @override
  void initState() {
    super.initState();
    _durationSub = _audioPlayer.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });
    _stateSub = _audioPlayer.onPlayerStateChanged.listen((s) {
      setState(() => _isPlaying = (s == PlayerState.playing));
    });
    _completeSub = _audioPlayer.onPlayerComplete.listen((event) {
      if (_playMode == 1) {
        _audioPlayer.resume();
      } else {
        _playNext();
      }
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateMultiSelectStatus(bool isMode, int count) {
    setState(() {
      _isMultiSelectMode = isMode;
      _selectedCount = count;
    });
  }

  void _handlePlay(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    setState(() {
      _currentPath = path;
      _currentTitle = path.split('/').last;
    });
  }

  void _addToQueue(List<FileSystemEntity> files) {
    int addedCount = 0;
    setState(() {
      for (var file in files) {
        if (!_playQueue.any((e) => e.path == file.path)) {
          _playQueue.add(file);
          addedCount++;
        }
      }
    });
    if (addedCount > 0) {
      _showCenterToast("已加入 $addedCount 首歌曲");
    }
  }

  void _clearQueue() {
    if (_playQueue.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("清空佇列"),
        content: const Text("確定要移除目前佇列中的所有歌曲嗎？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _playQueue.clear();
              });
              Navigator.pop(context);
            },
            child: const Text("確定", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _playNext() {
    if (_playQueue.isEmpty) return;
    int currentIndex = _playQueue.indexWhere(
      (file) => file.path == _currentPath,
    );
    int nextIndex = (_playMode == 2)
        ? Random().nextInt(_playQueue.length)
        : (currentIndex + 1) % _playQueue.length;
    _handlePlay(_playQueue[nextIndex].path);
  }

  void _playPrevious() {
    if (_playQueue.isEmpty) return;
    int currentIndex = _playQueue.indexWhere(
      (file) => file.path == _currentPath,
    );
    int prevIndex = (currentIndex - 1 + _playQueue.length) % _playQueue.length;
    _handlePlay(_playQueue[prevIndex].path);
  }

  void _onQueueReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final item = _playQueue.removeAt(oldIndex);
      _playQueue.insert(newIndex, item);
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  void _showCenterToast(String message) {
    OverlayState? overlayState = Overlay.of(context);
    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.5,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlayState.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 1), () {
      overlayEntry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜尋目前頁面...',
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() {}),
                )
              : Text(
                  _selectedIndex == 0
                      ? "播放佇列"
                      : (_selectedIndex == 1 ? "檔案總管" : "播放清單"),
                ),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _isSearching = !_isSearching;
                _searchController.clear();
              }),
            ),
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
            ),
            if (_selectedIndex == 1)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    _fileBrowserKey.currentState?._checkPermissionAndScan(),
              ),
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
                    isDark: _isDarkMode,
                    onFileTap: _handlePlay,
                    searchQuery: _searchController.text,
                    onReorder: _onQueueReorder,
                    onClear: _clearQueue,
                  ),
                  FileBrowserPage(
                    key: _fileBrowserKey,
                    searchQuery: _searchController.text,
                    isDark: _isDarkMode,
                    onFileTap: _handlePlay,
                    currentPlayingPath: _currentPath,
                    onBatchAdd: _addToQueue,
                    onSelectionChanged: _updateMultiSelectStatus,
                  ),
                  const Center(child: Text("播放清單")),
                ],
              ),
            ),
            const Divider(height: 1),
            // 動態工具列
            _isMultiSelectMode
                ? Container(
                    padding: const EdgeInsets.all(12),
                    color: colorScheme.primaryContainer,
                    child: Row(
                      children: [
                        Text(
                          "已選取 $_selectedCount 首",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              _fileBrowserKey.currentState?._performAdd(),
                          icon: const Icon(Icons.add_circle),
                          label: const Text("加入佇列"),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.favorite),
                          label: const Text("存為清單"),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              _fileBrowserKey.currentState?._cancelSelection(),
                        ),
                      ],
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    color: _isDarkMode
                        ? Colors.black38
                        : colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MarqueeText(
                          text: _currentTitle,
                          isScroll: _isPlaying,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(fontSize: 10),
                            ),
                            Expanded(
                              child: Slider(
                                value: _position.inSeconds.toDouble(),
                                max: _duration.inSeconds.toDouble() > 0
                                    ? _duration.inSeconds.toDouble()
                                    : 1.0,
                                onChanged: (v) => _audioPlayer.seek(
                                  Duration(seconds: v.toInt()),
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const IconButton(
                              icon: Icon(Icons.favorite_border),
                              onPressed: null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              onPressed: _selectedIndex == 0
                                  ? _playPrevious
                                  : null,
                            ),
                            IconButton(
                              iconSize: 48,
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                              ),
                              color: colorScheme.primary,
                              onPressed: () => _isPlaying
                                  ? _audioPlayer.pause()
                                  : _audioPlayer.resume(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              onPressed: _selectedIndex == 0 ? _playNext : null,
                            ),
                            IconButton(
                              icon: Icon(
                                _playMode == 0
                                    ? Icons.repeat
                                    : (_playMode == 1
                                          ? Icons.repeat_one
                                          : Icons.shuffle),
                              ),
                              color: colorScheme.primary,
                              onPressed: () => setState(
                                () => _playMode = (_playMode + 1) % 3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            Stack(
              children: [
                Container(
                  height: 4,
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment(
                    _selectedIndex == 0
                        ? -1.0
                        : (_selectedIndex == 1 ? 0.0 : 1.0),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / 3,
                    child: Container(height: 4, color: colorScheme.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) {
            if (_isMultiSelectMode)
              _fileBrowserKey.currentState?._cancelSelection();
            setState(() {
              _selectedIndex = i;
              _isSearching = false;
              _searchController.clear();
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.queue_music),
              label: '播放佇列',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_open),
              label: '檔案總管',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.playlist_play),
              label: '播放清單',
            ),
          ],
        ),
      ),
    );
  }
}

class QueuePage extends StatelessWidget {
  final List<FileSystemEntity> queue;
  final String currentPath;
  final bool isDark;
  final Function(String) onFileTap;
  final String searchQuery;
  final Function(int, int) onReorder;
  final VoidCallback onClear;
  const QueuePage({
    super.key,
    required this.queue,
    required this.currentPath,
    required this.isDark,
    required this.onFileTap,
    required this.searchQuery,
    required this.onReorder,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = queue
        .where(
          (f) => f.path
              .split('/')
              .last
              .toLowerCase()
              .contains(searchQuery.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: isDark ? Colors.black26 : Colors.grey[200],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "佇列共 ${filtered.length} 首",
                style: const TextStyle(fontSize: 12),
              ),
              if (queue.isNotEmpty)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.delete_sweep,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  label: const Text(
                    "清空",
                    style: TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: filtered.length,
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final file = filtered[index];
              final bool isSelected = file.path == currentPath;
              return ListTile(
                key: ValueKey(file.path),
                tileColor: isSelected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                leading: const Icon(Icons.menu),
                title: MarqueeText(
                  text: file.path.split('/').last,
                  isScroll: isSelected,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                subtitle: Text(
                  file.path,
                  style: const TextStyle(fontSize: 10),
                  maxLines: 1,
                ),
                onTap: () => onFileTap(file.path),
              );
            },
          ),
        ),
      ],
    );
  }
}

class FileBrowserPage extends StatefulWidget {
  final String searchQuery;
  final bool isDark;
  final Function(String) onFileTap;
  final String currentPlayingPath;
  final Function(List<FileSystemEntity>) onBatchAdd;
  final Function(bool, int) onSelectionChanged;
  const FileBrowserPage({
    super.key,
    required this.searchQuery,
    required this.isDark,
    required this.onFileTap,
    required this.currentPlayingPath,
    required this.onBatchAdd,
    required this.onSelectionChanged,
  });
  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileSystemEntity> _allFiles = [];
  final Set<String> _selectedPaths = {};
  bool _isScanning = false;
  bool _isMultiSelectMode = false;

  // 取消選取模式並清空已選路徑
  void _cancelSelection() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedPaths.clear();
    });
    widget.onSelectionChanged(false, 0);
  }

  // 執行將選中歌曲加入佇列
  void _performAdd() {
    if (_selectedPaths.isNotEmpty) {
      final toAdd = _allFiles
          .where((f) => _selectedPaths.contains(f.path))
          .toList();
      widget.onBatchAdd(toAdd);
      _cancelSelection();
    }
  }

  // 權限檢查與啟動掃描
  Future<void> _checkPermissionAndScan() async {
    if (_isScanning) return;
    var status = await Permission.audio.request();
    if (status.isGranted) {
      _startSafeScan();
    } else {
      // 可以在這裡處理權限被拒絕的提示
    }
  }

  // 核心掃描邏輯：遞迴尋找 MP3 與 M4A
  Future<void> _startSafeScan() async {
    setState(() => _isScanning = true);
    final rootDir = Directory('/storage/emulated/0');
    List<FileSystemEntity> found = [];

    Future<void> scan(Directory dir) async {
      try {
        final entities = dir.listSync(recursive: false);
        for (var e in entities) {
          if (e is File) {
            final path = e.path.toLowerCase();
            if (path.endsWith('.mp3') || path.endsWith('.m4a')) {
              found.add(e);
            }
          } else if (e is Directory && !e.path.contains('/Android')) {
            await scan(e);
          }
        }
      } catch (e) {
        // 靜默處理權限不足或系統資料夾讀取錯誤
      }
    }

    await scan(rootDir);
    if (mounted) {
      setState(() {
        _allFiles = found;
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allFiles
        .where(
          (f) => f.path
              .split('/')
              .last
              .toLowerCase()
              .contains(widget.searchQuery.toLowerCase()),
        )
        .toList();

    return Column(
      children: [
        // 副標題列 (Subtitle Bar)
        Container(
          width: double.infinity,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          color: widget.isDark ? Colors.black26 : Colors.grey[200],
          child: Text(
            "檔案庫找到 ${filtered.length} 首",
            style: const TextStyle(fontSize: 12),
          ),
        ),
        // 清單區
        Expanded(
          child: _isScanning
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final file = filtered[index];
                    final fileName = file.path.split('/').last;
                    final isChecked = _selectedPaths.contains(file.path);
                    final isPlaying = file.path == widget.currentPlayingPath;

                    return ListTile(
                      leading: _isMultiSelectMode
                          ? Checkbox(
                              value: isChecked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedPaths.add(file.path);
                                  } else {
                                    _selectedPaths.remove(file.path);
                                  }
                                });
                                widget.onSelectionChanged(
                                  true,
                                  _selectedPaths.length,
                                );
                              },
                            )
                          : const Icon(Icons.music_note),
                      title: MarqueeText(
                        text: fileName,
                        isScroll: isPlaying,
                        style: TextStyle(
                          fontWeight: isPlaying ? FontWeight.bold : null,
                          color: isPlaying
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        file.path,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onLongPress: () {
                        if (!_isMultiSelectMode) {
                          setState(() {
                            _isMultiSelectMode = true;
                            _selectedPaths.add(file.path);
                          });
                          widget.onSelectionChanged(
                            true,
                            _selectedPaths.length,
                          );
                        }
                      },
                      onTap: () {
                        if (_isMultiSelectMode) {
                          setState(() {
                            if (isChecked) {
                              _selectedPaths.remove(file.path);
                            } else {
                              _selectedPaths.add(file.path);
                            }
                          });
                          widget.onSelectionChanged(
                            true,
                            _selectedPaths.length,
                          );
                        } else {
                          widget.onFileTap(file.path);
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
