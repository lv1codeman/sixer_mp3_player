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
  bool _isPlaying = false;
  bool _isFavorite = false;

  // 0: 列表循環 (Repeat All), 1: 單曲循環 (Repeat One), 2: 隨機播放 (Shuffle)
  int _playMode = 0;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSub, _positionSub, _stateSub;

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

    // 播放結束後的處理
    _audioPlayer.onPlayerComplete.listen((event) {
      if (_playMode == 1) {
        _audioPlayer.resume(); // 單曲循環：直接重播
      } else {
        // 這裡預留給下一首 (下一階段實作)
      }
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handlePlay(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    setState(() => _currentTitle = path.split('/').last);
  }

  // 取得播放模式的圖示
  IconData _getPlayModeIcon() {
    switch (_playMode) {
      case 1:
        return Icons.repeat_one; // 單曲
      case 2:
        return Icons.shuffle; // 隨機
      default:
        return Icons.repeat; // 列表循環
    }
  }

  // 取得播放模式的文字描述 (可選)
  String _getPlayModeText() {
    switch (_playMode) {
      case 1:
        return "單曲播放";
      case 2:
        return "隨機播放";
      default:
        return "循環播放";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      ),
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;

          return Scaffold(
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
                      ),
                      const Center(child: Text("第三頁：播放清單")),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // --- 播放控制區 ---
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  color: _isDarkMode
                      ? Colors.black38
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
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

                      // 控制按鈕
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 1. 收藏鍵
                          IconButton(
                            icon: Icon(
                              _isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                            ),
                            color: _isFavorite ? Colors.red : null,
                            onPressed: () =>
                                setState(() => _isFavorite = !_isFavorite),
                          ),
                          // 2. 上一首
                          IconButton(
                            icon: const Icon(Icons.skip_previous),
                            onPressed: () {},
                          ),
                          // 3. 播放/暫停
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
                          // 4. 下一首
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            onPressed: () {},
                          ),
                          // 5. 整合後的播放模式切換鈕
                          IconButton(
                            icon: Icon(_getPlayModeIcon()),
                            color: colorScheme.primary,
                            onPressed: () {
                              setState(() {
                                _playMode = (_playMode + 1) % 3;
                              });
                              // 顯示提示
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("模式：${_getPlayModeText()}"),
                                  duration: const Duration(milliseconds: 500),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 分頁指示條
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
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }
}

// --- FileBrowserPage 保持不變 ---
class FileBrowserPage extends StatefulWidget {
  final String searchQuery;
  final bool isDark;
  final Function(String) onFileTap;
  const FileBrowserPage({
    super.key,
    required this.searchQuery,
    required this.isDark,
    required this.onFileTap,
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
    if (status.isGranted) _startSafeScan();
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
                path.endsWith('.wav'))
              foundFiles.add(entity);
          } else if (entity is Directory && !entity.path.contains('/Android')) {
            await safeScan(entity);
          }
        }
      } catch (e) {
        debugPrint("Skip: ${dir.path}");
      }
    }

    await safeScan(rootDir);
    if (mounted)
      setState(() {
        _allFiles = foundFiles;
        _isScanning = false;
      });
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
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.music_note),
                      ),
                      title: Text(
                        file.path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
