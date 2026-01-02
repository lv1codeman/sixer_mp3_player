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

  // --- 播放器狀態 ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentTitle = "未在播放";
  String _currentPath = ""; // 紀錄目前播放檔案的路徑
  bool _isPlaying = false;
  bool _isFavorite = false;
  int _playMode = 0;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSub, _positionSub, _stateSub, _completeSub;

  @override
  void initState() {
    super.initState();
    _durationSub = _audioPlayer.onDurationChanged.listen(
      (d) => setState(() => _duration = d),
    );
    _positionSub = _audioPlayer.onPositionChanged.listen(
      (p) => setState(() => _position = p),
    );
    _stateSub = _audioPlayer.onPlayerStateChanged.listen(
      (s) => setState(() => _isPlaying = s == PlayerState.playing),
    );
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

  void _showCenterToast(String message) {
    OverlayState? overlayState = Overlay.of(context);
    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.5,
        width: MediaQuery.of(context).size.width,
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(message),
            ),
          ),
        ),
      ),
    );
    overlayState.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 1), () => overlayEntry.remove());
  }

  void _handlePlay(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    setState(() {
      _currentPath = path;
      _currentTitle = path.split('/').last;
    });
  }

  void _playNext() {
    final browserState = _fileBrowserKey.currentState;
    if (browserState == null || browserState._allFiles.isEmpty) return;
    List<FileSystemEntity> list = browserState._allFiles;
    int currentIndex = list.indexWhere((file) => file.path == _currentPath);
    int nextIndex = _playMode == 2
        ? Random().nextInt(list.length)
        : (currentIndex + 1) % list.length;
    _handlePlay(list[nextIndex].path);
  }

  void _playPrevious() {
    final browserState = _fileBrowserKey.currentState;
    if (browserState == null || browserState._allFiles.isEmpty) return;
    List<FileSystemEntity> list = browserState._allFiles;
    int currentIndex = list.indexWhere((file) => file.path == _currentPath);
    int prevIndex = (currentIndex - 1 + list.length) % list.length;
    _handlePlay(list[prevIndex].path);
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
                    hintText: '搜尋歌曲...',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() {}),
                )
              : const Text('Sixer MP3 Player'),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              }),
            ),
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
            ),
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
                  const Center(child: Text("第一頁：播放佇列")),
                  FileBrowserPage(
                    key: _fileBrowserKey,
                    searchQuery: _searchController.text,
                    isDark: _isDarkMode,
                    onFileTap: _handlePlay,
                    currentPlayingPath: _currentPath, // 傳遞目前路徑給子頁面
                  ),
                  const Center(child: Text("第三頁：播放清單")),
                ],
              ),
            ),
            const Divider(height: 1),
            // 播放控制區
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
                  Slider(
                    value: _position.inSeconds.toDouble(),
                    max: _duration.inSeconds.toDouble() > 0
                        ? _duration.inSeconds.toDouble()
                        : 1.0,
                    onChanged: (v) =>
                        _audioPlayer.seek(Duration(seconds: v.toInt())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: const TextStyle(fontSize: 10),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isFavorite ? Icons.favorite : Icons.favorite_border,
                        ),
                        color: _isFavorite ? Colors.red : null,
                        onPressed: () =>
                            setState(() => _isFavorite = !_isFavorite),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _playPrevious,
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
                        onPressed: _playNext,
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
            // 指示條
            Stack(
              children: [
                Container(
                  height: 4,
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
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
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }
}

// --- FileBrowserPage 實作 ---
class FileBrowserPage extends StatefulWidget {
  final String searchQuery;
  final bool isDark;
  final Function(String) onFileTap;
  final String currentPlayingPath; // 新增：傳入目前播放路徑

  const FileBrowserPage({
    super.key,
    required this.searchQuery,
    required this.isDark,
    required this.onFileTap,
    required this.currentPlayingPath,
  });

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileSystemEntity> _allFiles = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndScan();
  }

  Future<void> _checkPermissionAndScan() async {
    if (_isScanning) return;
    var status = await Permission.audio.request();
    if (status.isGranted) {
      _startSafeScan();
    }
  }

  Future<void> _startSafeScan() async {
    setState(() => _isScanning = true);
    final rootDir = Directory('/storage/emulated/0');
    List<FileSystemEntity> foundFiles = [];
    Future<void> safeScan(Directory dir) async {
      try {
        final entities = dir.listSync(recursive: false);
        for (var entity in entities) {
          if (entity is File) {
            String path = entity.path.toLowerCase();
            if (path.endsWith('.mp3') ||
                path.endsWith('.m4a') ||
                path.endsWith('.wav')) {
              foundFiles.add(entity);
            }
          } else if (entity is Directory) {
            if (!entity.path.contains('/Android')) {
              await safeScan(entity);
            }
          }
        }
      } catch (e) {
        debugPrint("Skip: ${dir.path}");
      }
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
    final colorScheme = Theme.of(context).colorScheme;
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
          child: Text(
            "共找到  (${filteredFiles.length} 首)",
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isScanning
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filteredFiles.length,
                  itemBuilder: (context, index) {
                    final file = filteredFiles[index];
                    // --- 關鍵邏輯：比對路徑 ---
                    final bool isSelected =
                        file.path == widget.currentPlayingPath;

                    return ListTile(
                      // 若選中，背景變色
                      tileColor: isSelected
                          ? colorScheme.secondaryContainer
                          : null,
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? colorScheme.primary
                            : colorScheme.primaryContainer,
                        child: Icon(
                          isSelected ? Icons.volume_up : Icons.music_note,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        file.path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onSecondaryContainer
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        file.path,
                        style: const TextStyle(fontSize: 10),
                      ),
                      onTap: () => widget.onFileTap(file.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
