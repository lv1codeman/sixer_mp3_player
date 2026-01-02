import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const SixerMP3Player());

class SixerMP3Player extends StatelessWidget {
  const SixerMP3Player({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sixer MP3 Player',
      // 設定預設主題
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              // T2-2: 搜尋狀態切換標題
              title: _isSearching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: const InputDecoration(
                        hintText: '搜尋歌曲...',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                    )
                  : const Text('Sixer MP3 Player'),
              centerTitle: false,
              actions: [
                // 搜尋按鈕
                if (_isSearching) ...[
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchController.clear();
                      });
                    },
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                ],
                // 主題切換按鈕
                IconButton(
                  icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () {
                    setState(() {
                      _isDarkMode = !_isDarkMode;
                    });
                  },
                ),
                // 重新整理按鈕
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _fileBrowserKey.currentState?._checkPermissionAndScan();
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                // 主要內容區
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      const Center(child: Text("第一頁：播放佇列")),
                      FileBrowserPage(
                        key: _fileBrowserKey,
                        searchQuery: _searchController.text,
                        isDark: _isDarkMode,
                      ),
                      const Center(child: Text("第三頁：播放清單")),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 底部播放控制欄
                Container(
                  height: 80,
                  color: _isDarkMode
                      ? Colors.black26
                      : Colors.deepPurple.withValues(alpha: 0.1),
                  child: const Center(child: Text("播放控制欄 (待實作)")),
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
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
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
          );
        },
      ),
    );
  }
}

// --- FileBrowserPage 實作 ---

class FileBrowserPage extends StatefulWidget {
  final String searchQuery;
  final bool isDark;
  const FileBrowserPage({
    super.key,
    required this.searchQuery,
    required this.isDark,
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
        debugPrint("跳過無法存取的目錄: ${dir.path}");
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

    // 搜尋過濾
    final filteredFiles = _allFiles.where((file) {
      final name = file.path.split('/').last.toLowerCase();
      return name.contains(widget.searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // 修改後的狀態顯示欄
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
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.music_note,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        file.path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        file.path,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () {
                        // 下一階段播放邏輯
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
