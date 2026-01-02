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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light, // T2-1 預計會改這裡
      ),
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
  int _selectedIndex = 1; // 預設直接開到第二頁「檔案總管」方便測試

  // 這裡就是你剛才找的 _pages 區塊
  final List<Widget> _pages = [
    const Center(child: Text("第一頁：播放佇列 (待實作)")),
    const FileBrowserPage(), // 實作 P-1 的核心頁面
    const Center(child: Text("第三頁：播放清單 (待實作)")),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sixer MP3 Player'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
          const Divider(height: 1),
          // 底部播放器佔位
          Container(
            height: 80,
            color: Colors.deepPurple.withOpacity(0.1),
            child: const Center(child: Text("播放控制欄 (待實作)")),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: '播放佇列'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_open), label: '檔案總管'),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play),
            label: '播放清單',
          ),
        ],
      ),
    );
  }
}

// --- P-1 檔案總管實作頁面 ---

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

  // 檢查權限
  Future<void> _checkPermissionAndScan() async {
    // 針對 Android 13+ (你的 POCO F8 Ultra 應該是這之後的版本)
    var status = await Permission.audio.request();

    if (status.isGranted) {
      _startScan();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("請授予音訊存取權限以掃描音樂")));
      }
    }
  }

  // 掃描目錄 (P-1 核心邏輯)
  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    // Android 的外部儲存根目錄
    final directory = Directory('/storage/emulated/0');
    List<FileSystemEntity> foundFiles = [];

    try {
      if (await directory.exists()) {
        // 取得所有檔案 (遞迴掃描)
        final List<FileSystemEntity> allEntities = directory.listSync(
          recursive: true,
          followLinks: false,
        );

        for (var entity in allEntities) {
          if (entity is File &&
              (entity.path.endsWith('.mp3') ||
                  entity.path.endsWith('.m4a') ||
                  entity.path.endsWith('.wav'))) {
            foundFiles.add(entity);
          }
        }
      }
    } catch (e) {
      debugPrint("掃描時發生錯誤: $e");
    }

    if (mounted) {
      setState(() {
        _musicFiles = foundFiles;
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text("找到 ${_musicFiles.length} 首歌曲"),
          trailing: _isScanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _checkPermissionAndScan,
                ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _musicFiles.isEmpty && !_isScanning
              ? const Center(child: Text("沒找到音樂檔案，請確認手機內是否有 MP3"))
              : ListView.builder(
                  itemCount: _musicFiles.length,
                  itemBuilder: (context, index) {
                    final file = _musicFiles[index];
                    final fileName = file.path.split('/').last;
                    return ListTile(
                      leading: const Icon(
                        Icons.music_note,
                        color: Colors.deepPurple,
                      ),
                      title: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        file.path,
                        style: const TextStyle(fontSize: 10),
                      ),
                      onTap: () {
                        // 未來在這裡實作點擊播放
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
