import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const SixerMP3Player());

class SixerMP3Player extends StatelessWidget {
  const SixerMP3Player({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sixer MP3 Player2',
      // 設定淺色主題
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      // T2-1: 設定深色主題
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      // 根據手機系統設定自動切換深淺色
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
  int _selectedIndex = 1; // 預設停在檔案總管分頁
  bool _isDarkMode = false;

  final List<Widget> _pages = [
    const Center(child: Text("第一頁：播放佇列 (待實作)")),
    const FileBrowserPage(), // P-1 實作內容
    const Center(child: Text("第三頁：播放清單 (待實作)")),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      // 根據 _isDarkMode 決定局部主題
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sixer MP3 Player'),
          centerTitle: true,
          // 這是你找的切換 Icon 按鈕！
          actions: [
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                // 注意：這裡要把 _pages 移到 build 裡面，
                // 這樣切換主題時，子頁面才會跟著重繪顏色
                children: [
                  const Center(child: Text("第一頁：播放佇列 (待實作)")),
                  const FileBrowserPage(),
                  const Center(child: Text("第三頁：播放清單 (待實作)")),
                ],
              ),
            ),

            const Divider(height: 1),
            Container(
              height: 80,
              // 使用 Theme.of(context) 確保顏色同步
              color: _isDarkMode
                  ? Colors.black26
                  : Colors.deepPurple.withValues(alpha: 0.1),
              child: const Center(child: Text("播放控制欄 (待實作)")),
            ),
            // --- 指示條 (Indicator Bar) ---
            Stack(
              children: [
                // 底色條
                Container(
                  height: 4,
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                ),
                // 動態移動的指示塊
                AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  // 這裡計算對齊位置：-1.0 是最左，0.0 是中間，1.0 是最右
                  alignment: Alignment(
                    _selectedIndex == 0
                        ? -1.0
                        : (_selectedIndex == 1 ? 0.0 : 1.0),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / 3, // 三個分頁，寬度佔三分之一
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
          onTap: (index) => setState(() => _selectedIndex = index),
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

// --- P-1 檔案總管實作頁面 (包含 T2-1 配色優化) ---

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileSystemEntity> _musicFiles = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndScan();
  }

  // 1. 請求權限 (針對 Android 13+ 的 POCO F8 Ultra 優化)
  Future<void> _checkPermissionAndScan() async {
    var status = await Permission.audio.request();
    if (status.isGranted) {
      _startSafeScan();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("請在系統設定中授予音訊存取權限")));
      }
    }
  }

  // 2. 安全掃描邏輯：跳過受保護的 Android/data 等資料夾
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
            // 過濾副檔名
            if (path.endsWith('.mp3') ||
                path.endsWith('.m4a') ||
                path.endsWith('.wav')) {
              foundFiles.add(entity);
            }
          } else if (entity is Directory) {
            // 關鍵：跳過會導致 Permission Denied 的系統目錄
            if (entity.path.contains('/Android')) continue;
            await safeScan(entity);
          }
        }
      } catch (e) {
        debugPrint("跳過無法存取的目錄: ${dir.path}");
      }
    }

    await safeScan(rootDir);

    if (mounted) {
      setState(() {
        _musicFiles = foundFiles;
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 取得當前主題配色方案 (T2-1)
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 頂部狀態欄
        ListTile(
          tileColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          title: Text(
            "找到 ${_musicFiles.length} 首歌曲",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          trailing: _isScanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: Icon(Icons.refresh, color: colorScheme.primary),
                  onPressed: _checkPermissionAndScan,
                ),
        ),
        const Divider(height: 1),
        // 音樂檔案列表
        Expanded(
          child: _musicFiles.isEmpty && !_isScanning
              ? const Center(child: Text("沒找到音樂檔案，請確認手機 Download 資料夾是否有 MP3"))
              : ListView.builder(
                  itemCount: _musicFiles.length,
                  itemBuilder: (context, index) {
                    final file = _musicFiles[index];
                    final fileName = file.path.split('/').last;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.music_note,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        file.path,
                        style: TextStyle(
                          fontSize: 10,
                          // T2-1: 自動切換半透明感的文字顏色
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () {
                        // TODO: 實作加入播放佇列邏輯
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
