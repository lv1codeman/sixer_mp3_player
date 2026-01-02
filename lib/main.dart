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

  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<FileSystemEntity> _playQueue = [];
  String _currentTitle = "未在播放";
  String _currentPath = "";
  bool _isPlaying = false;
  int _playMode = 0;

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
      setState(() => _isPlaying = s == PlayerState.playing);
    });
    _completeSub = _audioPlayer.onPlayerComplete.listen((event) {
      if (_selectedIndex == 0) {
        if (_playMode == 1) {
          _audioPlayer.resume();
        } else {
          _playNext();
        }
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
                  color: Colors.black.withValues(alpha: 0.7),
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
    } else {
      _showCenterToast("歌曲已存在於佇列中");
    }
  }

  void _playNext() {
    if (_playQueue.isEmpty) {
      return;
    }
    int currentIndex = _playQueue.indexWhere(
      (file) => file.path == _currentPath,
    );
    int nextIndex = _playMode == 2
        ? Random().nextInt(_playQueue.length)
        : (currentIndex + 1) % _playQueue.length;
    _handlePlay(_playQueue[nextIndex].path);
  }

  void _playPrevious() {
    if (_playQueue.isEmpty) {
      return;
    }
    int currentIndex = _playQueue.indexWhere(
      (file) => file.path == _currentPath,
    );
    int prevIndex = (currentIndex - 1 + _playQueue.length) % _playQueue.length;
    _handlePlay(_playQueue[prevIndex].path);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
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
                  onChanged: (value) => setState(() {}),
                )
              : Text(
                  _selectedIndex == 0
                      ? "播放佇列"
                      : (_selectedIndex == 1 ? "檔案總管" : "播放清單"),
                ),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  _searchController.clear();
                });
              },
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
                  ),
                  FileBrowserPage(
                    key: _fileBrowserKey,
                    searchQuery: _searchController.text,
                    isDark: _isDarkMode,
                    onFileTap: _handlePlay,
                    currentPlayingPath: _currentPath,
                    onBatchAdd: _addToQueue,
                  ),
                  const Center(child: Text("播放清單")),
                ],
              ),
            ),
            const Divider(height: 1),
            // --- 控制區 ---
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: _isDarkMode
                  ? Colors.black38
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                          onChanged: (v) =>
                              _audioPlayer.seek(Duration(seconds: v.toInt())),
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
                        onPressed: _selectedIndex == 0 ? _playPrevious : null,
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
                      _selectedIndex == 1
                          ? IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              color: colorScheme.primary,
                              onPressed: () => _fileBrowserKey.currentState
                                  ?._addSelectedToQueue(),
                            )
                          : IconButton(
                              icon: Icon(
                                _playMode == 0
                                    ? Icons.repeat
                                    : (_playMode == 1
                                          ? Icons.repeat_one
                                          : Icons.shuffle),
                              ),
                              color: colorScheme.primary,
                              onPressed: () {
                                setState(() => _playMode = (_playMode + 1) % 3);
                                _showCenterToast(
                                  _playMode == 0
                                      ? "循環播放"
                                      : (_playMode == 1 ? "單曲播放" : "隨機播放"),
                                );
                              },
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) {
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

// --- 其餘 QueuePage 與 FileBrowserPage 邏輯同上，僅修正 if 語法 ---
class QueuePage extends StatelessWidget {
  final List<FileSystemEntity> queue;
  final String currentPath;
  final bool isDark;
  final Function(String) onFileTap;
  final String searchQuery;

  const QueuePage({
    super.key,
    required this.queue,
    required this.currentPath,
    required this.isDark,
    required this.onFileTap,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final filteredQueue = queue
        .where(
          (file) => file.path
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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: isDark ? Colors.black26 : Colors.grey[200],
          child: Text(
            "佇列中找到 ${filteredQueue.length} 首",
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredQueue.length,
            itemBuilder: (context, index) {
              final file = filteredQueue[index];
              final bool isSelected = file.path == currentPath;
              return ListTile(
                tileColor: isSelected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                leading: Icon(isSelected ? Icons.volume_up : Icons.music_note),
                title: Text(
                  file.path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
  const FileBrowserPage({
    super.key,
    required this.searchQuery,
    required this.isDark,
    required this.onFileTap,
    required this.currentPlayingPath,
    required this.onBatchAdd,
  });

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileSystemEntity> _allFiles = [];
  final Set<String> _selectedPaths = {};
  bool _isScanning = false;
  bool _isMultiSelectMode = false;

  void _addSelectedToQueue() {
    if (_isMultiSelectMode && _selectedPaths.isNotEmpty) {
      List<FileSystemEntity> toAdd = _allFiles
          .where((f) => _selectedPaths.contains(f.path))
          .toList();
      widget.onBatchAdd(toAdd);
      setState(() {
        _isMultiSelectMode = false;
        _selectedPaths.clear();
      });
    } else {
      final currentFile = _allFiles
          .where((f) => f.path == widget.currentPlayingPath)
          .toList();
      if (currentFile.isNotEmpty) {
        widget.onBatchAdd(currentFile);
      }
    }
  }

  Future<void> _checkPermissionAndScan() async {
    if (_isScanning) {
      return;
    }
    var status = await Permission.audio.request();
    if (status.isGranted) {
      _startSafeScan();
    }
  }

  Future<void> _startSafeScan() async {
    setState(() {
      _isScanning = true;
    });
    final rootDir = Directory('/storage/emulated/0');
    List<FileSystemEntity> foundFiles = [];
    Future<void> safeScan(Directory dir) async {
      try {
        final entities = dir.listSync(recursive: false);
        for (var entity in entities) {
          if (entity is File) {
            String path = entity.path.toLowerCase();
            if (path.endsWith('.mp3') || path.endsWith('.m4a')) {
              foundFiles.add(entity);
            }
          } else if (entity is Directory && !entity.path.contains('/Android')) {
            await safeScan(entity);
          }
        }
      } catch (e) {}
    }

    await safeScan(rootDir);
    if (mounted) {
      setState(() {
        _allFiles = foundFiles;
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredFiles = _allFiles
        .where(
          (file) => file.path
              .split('/')
              .last
              .toLowerCase()
              .contains(widget.searchQuery.toLowerCase()),
        )
        .toList();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: widget.isDark ? Colors.black26 : Colors.grey[200],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "檔案庫找到 (${filteredFiles.length} 首)",
                style: const TextStyle(fontSize: 12),
              ),
              if (_isMultiSelectMode)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isMultiSelectMode = false;
                      _selectedPaths.clear();
                    });
                  },
                  child: const Text("取消多選", style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isScanning
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filteredFiles.length,
                  itemBuilder: (context, index) {
                    final file = filteredFiles[index];
                    final bool isSelected =
                        file.path == widget.currentPlayingPath;
                    final bool isChecked = _selectedPaths.contains(file.path);

                    return ListTile(
                      tileColor: isSelected
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : null,
                      leading: _isMultiSelectMode
                          ? Checkbox(
                              value: isChecked,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedPaths.add(file.path);
                                  } else {
                                    _selectedPaths.remove(file.path);
                                  }
                                });
                              },
                            )
                          : Icon(
                              isSelected ? Icons.headphones : Icons.music_note,
                            ),
                      title: Text(
                        file.path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        file.path,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                      ),
                      onLongPress: () {
                        setState(() {
                          _isMultiSelectMode = true;
                          _selectedPaths.add(file.path);
                        });
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
