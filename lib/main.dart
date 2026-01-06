import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

// 程式碼分區管理
import 'models/song.dart';
import 'utils/utils.dart';
// import 'widgets/sub_header.dart';
// import 'widgets/highlighted_text.dart';

import 'pages/queue_page.dart';
import 'pages/file_browser_page.dart';
import 'pages/favorite_page.dart';
import 'pages/playlist_page.dart';
import 'services/audio_handler.dart';

// 建立全域的 AudioHandler 實例
late MyAudioHandler _audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化背景播放服務
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.sixer.mp3.channel.audio',
      androidNotificationChannelName: 'SixerMP3 播放控制',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const SixerMP3Player());
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
      navigatorKey: navigatorKey,
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

enum PlaySource { queue, all, favorites } //播放來源：佇列、瀏覽、收藏

class MainScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const MainScreen({super.key, required this.onToggleTheme});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 1;
  late PageController _pageController;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<FileBrowserPageState> _fileBrowserKey = GlobalKey();

  final List<Song> _playQueue = []; // 播放器的歌曲總表
  final List<Song> _allSongs = []; // 瀏覽頁面的歌曲總表
  bool _isScanning = false;
  String _currentPath = "";
  String _currentTitle = "未在播放";
  bool _isPlaying = false;
  int _playMode = 0; // 0: 列表, 1: 單曲, 2: 隨機
  bool _isSwitchingTrack = false;

  final Set<String> _favorites = {};
  final Map<String, List<String>> _playlists = {};

  bool _isMultiSelectMode = false;
  int _selectedCount = 0;
  String _selectedTotalTime = "00:00";
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isDragging = false;
  PlaySource _activeSource = PlaySource.queue;

  List<Song> get _currentPlayingList {
    switch (_activeSource) {
      case PlaySource.favorites:
        // 從總表中過濾出收藏的歌曲
        return _allSongs.where((s) => _favorites.contains(s.path)).toList();
      case PlaySource.all:
        return _allSongs;
      case PlaySource.queue:
        return _playQueue;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // _initData();
    _audioHandler.onSkipNext = _handleNext;
    _audioHandler.onSkipPrevious = _handlePrevious;
    _pageController = PageController(initialPage: _selectedIndex);
    _loadData().then((_) {
      // 確保資料載入後，自動執行掃描
      // 使用 WidgetsBinding 確保在第一幀渲染完成後執行，避免與 UI 構建衝突
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkPermissionAndScan();
      });
    });
    // [修改] 監聽背景播放狀態，同步 UI 按鈕
    _audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (!_isDragging) {
            _position = state.updatePosition;
          }
        });
      }
    });
    _audioHandler.mediaItem.listen((item) {
      if (item != null && mounted) {
        setState(() {
          // 取代 onDurationChanged
          _duration = item.duration ?? Duration.zero;
          // 同步當前路徑與標題
          _currentPath = item.id;
          _currentTitle = item.title;
        });
      }
    });
    _audioHandler.onComplete = _handleNext;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndScan() async {
    // 適配 Android 13+
    bool hasPermission = false;
    if (Platform.isAndroid) {
      hasPermission =
          await Permission.audio.request().isGranted ||
          await Permission.storage.request().isGranted;
    }

    if (hasPermission) {
      setState(() {
        _isScanning = true;
        _allSongs.clear();
      });

      final root = Directory('/storage/emulated/0');
      final List<Song> tempSongs = []; // 使用暫存清單

      try {
        // 1. 快速掃描路徑，暫時不讀取 AudioTags
        await for (var entity
            in root
                .list(recursive: true, followLinks: false)
                .handleError((e) {})) {
          if (entity is File &&
              entity.path.toLowerCase().endsWith('.mp3') &&
              !entity.path.contains('/Android/')) {
            // 這裡先給 Duration.zero，追求最快掃描速度

            final player = AudioPlayer();
            Duration? d;
            try {
              // 這會稍微增加掃描時間，但能獲得正確時長
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

            // 每找到 20 首歌更新一次 UI，兼顧進度顯示與效能
            if (tempSongs.length % 20 == 0) {
              if (mounted) {
                setState(() {
                  _allSongs.clear(); // 先清空原本的內容
                  _allSongs.addAll(tempSongs); // 再把掃描到的新歌加進去
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
          // [修正] 不能直接賦值，改用 clear + addAll
          _allSongs.clear();
          _allSongs.addAll(tempSongs);
          _isScanning = false;
        });
        _saveData(); // 掃描完存檔
      }
    } else {
      myToast("未取得讀取權限");
    }
  }

  void _onBottomNavTapped(int index) {
    if (_isMultiSelectMode) {
      _fileBrowserKey.currentState?.cancelSelection();
    }
    setState(() {
      _selectedIndex = index;
    });
    // 2. 讓 PageView 動畫跳轉到指定頁面
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
    final currentList = _currentPlayingList;
    if (currentList.isEmpty) return;

    int idx = currentList.indexWhere((s) => s.path == _currentPath);
    int prevIdx;

    if (_playMode == 2) {
      prevIdx = Random().nextInt(currentList.length);
    } else {
      prevIdx = (idx - 1 + currentList.length) % currentList.length;
    }
    _handlePlay(currentList[prevIdx].path);
  }

  void _handleNext() {
    // 1. 取得目前的動態播放清單（依據 _activeSource 決定）
    final currentList = _currentPlayingList;
    if (currentList.isEmpty) {
      return;
    }
    // 2. 找出目前播放路徑在該清單中的位置
    int idx = currentList.indexWhere((s) {
      return s.path == _currentPath;
    });
    int nextIdx;
    // 3. 處理隨機播放邏輯 (_playMode == 2)
    if (_playMode == 2) {
      nextIdx = Random().nextInt(currentList.length);
    } else {
      // 4. 處理循序或單曲循環 (_playMode 0 或 1)
      nextIdx = (idx + 1) % currentList.length;
    }
    // 5. 執行播放
    _handlePlay(currentList[nextIdx].path);
  }

  void _handlePlay(String path) async {
    debugPrint(">>> [HandlePlay] 收到點擊請求: $path");
    if (_isSwitchingTrack) return;
    debugPrint(">>> [HandlePlay] 請求被攔截：播放器正在切換中 (isSwitchingTrack = true)");
    _isSwitchingTrack = true;
    try {
      setState(() {
        _position = Duration.zero;
        _currentPath = path;
        _currentTitle = path.split('/').last;
        _isDragging = false;
      });
      // 透過 handler 播放，這樣通知列才會同步更新
      await _audioHandler.playPath(path).timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint("播放失敗: $e");
      _isSwitchingTrack = false; // 發生錯誤立即解鎖
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingTrack = false;
        });
      }
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
    _saveData();
  }

  // 刪除單曲邏輯
  void _handleDeleteFromQueue(int index) {
    final String removedPath = _playQueue[index].path;
    setState(() {
      _playQueue.removeAt(index);
      // 如果刪除的是正在播放的，停止播放
      if (removedPath == _currentPath) {
        _audioHandler.stop(); // 停止播放
        _currentPath = ""; // 清空路徑
        _currentTitle = "未在播放"; // 重設標題
        _position = Duration.zero; // 重設進度條
        _duration = Duration.zero;
      }
    });
    _saveData();
  }

  void _clearQueue() async {
    await _audioHandler.stop();
    if (mounted) {
      setState(() {
        _playQueue.clear();
        _currentPath = "";
        _currentTitle = "未在播放";
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
      });
    }
    await _saveData();
  }

  void _addPlaylistToQueue(String playlistName) {
    // debugPrint("播放清單被按囉!!!!!!!!!!!!!!!!!!");
    final paths = _playlists[playlistName];
    if (paths != null) {
      setState(() {
        _playQueue.clear();
        for (var path in paths) {
          bool alreadyIn = _playQueue.any((s) {
            return s.path == path;
          });
          if (!alreadyIn) {
            try {
              final existingSong = _allSongs.firstWhere((s) => s.path == path);
              _playQueue.add(existingSong);
            } catch (e) {
              // 如果總表找不到，才建立新的（這時才可能沒時間）
              _playQueue.add(
                Song(
                  path: path,
                  title: path.split('/').last,
                  duration: Duration.zero,
                ),
              );
            }
          }
        }
        debugPrint("播放清單被按囉!!!!!!!!!!!!!!!!!!$_selectedIndex");
        _selectedIndex = 0; // 跳轉到佇列頁面
        _pageController.jumpToPage(0);
      });
    }
    _saveData();
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
                        // 去除重複歌曲
                        _playlists[finalName] = _playlists[finalName]!
                            .toSet()
                            .toList();
                      });
                      _saveData();
                      Navigator.pop(ctx);
                      myToast("已加入清單：$finalName");
                      // 另存後清空
                      _fileBrowserKey.currentState?.cancelSelection();
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

      // --- 新增：載入佇列歌曲 ---
      final String? queueJson = prefs.getString('queue');
      if (queueJson != null) {
        final List<dynamic> decodedQueue = jsonDecode(queueJson);
        _playQueue.clear();
        _playQueue.addAll(
          decodedQueue.map((item) => Song.fromJson(item)).toList(),
        );
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fav', jsonEncode(_favorites.toList()));
    await prefs.setString('list', jsonEncode(_playlists));

    // --- 新增：儲存佇列歌曲 ---
    final String queueJson = jsonEncode(
      _playQueue.map((s) => s.toJson()).toList(),
    );
    await prefs.setString('queue', queueJson);
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
          if (!_isSearching && isBrowser) ...{
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _checkPermissionAndScan();
              },
            ),
          },
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
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              // 3. 當手指滑動頁面完成後，同步更新底部的索引狀態
              onPageChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              children: [
                QueuePage(
                  queue: _playQueue,
                  currentPath: _currentPath,
                  query: _searchController.text,
                  format: _formatDuration,
                  onPlay: (path) {
                    setState(() {
                      // 關鍵！設定播放來源為「佇列」
                      _activeSource = PlaySource.queue;
                    });
                    _handlePlay(path);
                  },
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
                  allSongs: _allSongs, // 傳入主畫面的清單
                  currentQueue: _playQueue,
                  currentPath: _currentPath,
                  isScanning: _isScanning, // 傳入主畫面的掃描狀態
                  onScan: _checkPermissionAndScan, // 傳入主畫面的掃描函數
                  key: _fileBrowserKey,
                  query: _searchController.text,
                  format: _formatDuration,
                  favorites: _favorites,
                  onPlay: (path) {
                    setState(() {
                      // 關鍵！設定播放來源為「所有歌曲總表」
                      _activeSource = PlaySource.all;
                    });
                    _handlePlay(path);
                  },
                  onToggleFav: _toggleFav,
                  onBatchAdd: (songs) {
                    setState(() {
                      _playQueue.addAll(songs);
                    });
                    _saveData();
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
                  onPlay: (path) {
                    setState(() {
                      // 關鍵！設定播放來源為「收藏」
                      _activeSource = PlaySource.favorites;
                    });
                    _handlePlay(path);
                  },
                  onToggle: _toggleFav,
                ),
                PlaylistPage(
                  playlists: _playlists,
                  query: _searchController.text,
                  onPlaylistTap: _addPlaylistToQueue,
                  onDataChanged: () {
                    setState(
                      () {},
                    ); //playlist delete的時候也會用到，沒有setState的話不會刷新，就看不到清單刪除
                    _saveData();
                  },
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
                                _fileBrowserKey.currentState?.performAdd();
                                _pageController.jumpToPage(0);
                              },
                              icon: const Icon(Icons.queue_music),
                              label: const Text("加入佇列"),
                            ),
                            // 2. 另存播放清單
                            ElevatedButton.icon(
                              icon: const Icon(Icons.playlist_add),
                              label: const Text("另存清單"),
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
                            ),
                            // 3. 取消按鈕
                            TextButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text("取消"),
                              onPressed: () {
                                _fileBrowserKey.currentState?.cancelSelection();
                              },
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
                        Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          // 當前播放曲目文字
                          child: Text(
                            _currentTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 播放進度條
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: StreamBuilder<Duration>(
                            // [關鍵修正] 改為監聽 positionStream，這是 just_audio 內建會持續跳動的流
                            stream: _audioHandler.positionStream,
                            builder: (context, snapshot) {
                              // 取得當前播放器的實際位置
                              final position = snapshot.data ?? _position;

                              // 只有在沒拖動時才更新全域 _position
                              if (!_isDragging) {
                                _position = position;
                              }

                              return Row(
                                children: [
                                  // 左側時間
                                  SizedBox(
                                    width: 42,
                                    child: Text(
                                      _formatDuration(_position),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),

                                  // 中間 Slider
                                  Expanded(
                                    child: Slider(
                                      activeColor: colorScheme.primary,
                                      value: _position.inSeconds
                                          .toDouble()
                                          .clamp(
                                            0.0,
                                            _duration.inSeconds.toDouble() > 0
                                                ? _duration.inSeconds.toDouble()
                                                : 0.0,
                                          ),
                                      min: 0.0,
                                      max: _duration.inSeconds.toDouble() > 0
                                          ? _duration.inSeconds.toDouble()
                                          : 0.0,
                                      onChangeStart: (value) =>
                                          _isDragging = true,
                                      onChanged: (value) {
                                        setState(() {
                                          _position = Duration(
                                            seconds: value.toInt(),
                                          );
                                        });
                                      },
                                      onChangeEnd: (value) async {
                                        await _audioHandler.seek(
                                          Duration(seconds: value.toInt()),
                                        );
                                        await Future.delayed(
                                          const Duration(milliseconds: 200),
                                        );
                                        _isDragging = false;
                                      },
                                    ),
                                  ),

                                  // 右側總時長
                                  SizedBox(
                                    width: 42,
                                    child: Text(
                                      _formatDuration(_duration),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 收藏按鈕
                            IconButton(
                              icon: Icon(
                                _favorites.contains(_currentPath)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: Colors.red,
                              ),
                              iconSize: 28,
                              onPressed: () {
                                _toggleFav(_currentPath);
                              },
                            ),
                            // 上一首按鈕
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              onPressed: _handlePrevious,
                              iconSize: 40,
                            ),
                            // 播放/暫停 按鈕
                            IconButton(
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                              ),
                              iconSize: 64,
                              color: colorScheme.primary,
                              onPressed: () {
                                if (_isPlaying) {
                                  _audioHandler.pause();
                                } else {
                                  _audioHandler.play();
                                }
                              },
                            ),
                            // 下一首按鈕
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              onPressed: _handleNext,
                              iconSize: 40,
                            ),
                            // 播放模式按鈕
                            IconButton(
                              icon: Icon(
                                _playMode == 0
                                    ? Icons.repeat
                                    : (_playMode == 1
                                          ? Icons.repeat_one
                                          : Icons.shuffle),
                              ),
                              iconSize: 28,
                              onPressed: () {
                                setState(() {
                                  _playMode = (_playMode + 1) % 3;
                                  switch (_playMode) {
                                    case 0:
                                      _audioHandler.setLoopMode(LoopMode.off);
                                      myToast(
                                        "播放模式：全部循環",
                                        durationSeconds: 1.5,
                                      );
                                      break;
                                    case 1:
                                      _audioHandler.setLoopMode(LoopMode.one);
                                      myToast(
                                        "播放模式：單曲循環",
                                        durationSeconds: 1.5,
                                      );
                                      break;
                                    case 2:
                                      _audioHandler.setLoopMode(LoopMode.off);
                                      myToast(
                                        "播放模式：隨機循環",
                                        durationSeconds: 1.5,
                                      );
                                      break;
                                    default:
                                      _audioHandler.setLoopMode(LoopMode.off);
                                      myToast(
                                        "播放模式：全部循環",
                                        durationSeconds: 1.5,
                                      );
                                  }
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
            onTap: _onBottomNavTapped,
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

/// 已搬移的功能
/** 
// --- 1. 佇列頁面 ---
// class QueuePage extends StatelessWidget {
//   final List<Song> queue;
//   final String currentPath;
//   final String query;
//   final String Function(Duration) format;
//   final Function(String) onPlay;
//   final VoidCallback onClear;
//   final Function(int, int) onReorder;
//   final Function(int) onDelete;
//   final VoidCallback onSaveAsPlaylist;

//   const QueuePage({
//     super.key,
//     required this.queue,
//     required this.currentPath,
//     required this.query,
//     required this.format,
//     required this.onPlay,
//     required this.onClear,
//     required this.onReorder,
//     required this.onDelete,
//     required this.onSaveAsPlaylist,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final filtered = queue.where((s) {
//       return s.fileName.toLowerCase().contains(query.toLowerCase());
//     }).toList();

//     final totalDuration = filtered.fold(
//       Duration.zero,
//       (p, s) => p + s.duration,
//     );

//     return Column(
//       children: [
//         SubHeader(
//           text: "佇列：${filtered.length} 首 (${format(totalDuration)})",
//           trailing: filtered.isNotEmpty
//               ? Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     // 新增：加入清單鈕 (在左邊)
//                     TextButton.icon(
//                       onPressed: onSaveAsPlaylist,
//                       icon: const Icon(Icons.playlist_add, size: 18),
//                       label: const Text("加入清單", style: TextStyle(fontSize: 12)),
//                       style: TextButton.styleFrom(
//                         visualDensity: VisualDensity.compact,
//                       ),
//                     ),
//                     // 原本的清空鈕 (在右邊)
//                     TextButton.icon(
//                       onPressed: onClear,
//                       icon: const Icon(
//                         Icons.delete_sweep,
//                         size: 18,
//                         color: Colors.redAccent,
//                       ),
//                       label: const Text(
//                         "清空",
//                         style: TextStyle(fontSize: 12, color: Colors.redAccent),
//                       ),
//                       style: TextButton.styleFrom(
//                         visualDensity: VisualDensity.compact,
//                       ),
//                     ),
//                   ],
//                 )
//               : null,
//         ),

//         // --- 1. 佇列頁面 (QueuePage) ---
//         // ... 前方代碼不變 ...
//         Expanded(
//           child: ReorderableListView.builder(
//             onReorder: (oldIdx, newIdx) {
//               final int realOldIdx = queue.indexOf(filtered[oldIdx]);
//               int realNewIdx = queue.indexOf(
//                 filtered[newIdx > oldIdx ? newIdx - 1 : newIdx],
//               );
//               if (newIdx > oldIdx) {
//                 realNewIdx++;
//               }
//               onReorder(realOldIdx, realNewIdx);
//             },
//             buildDefaultDragHandles: false,
//             itemCount: filtered.length,
//             // 在 main.dart 約第 1020 行處修改
//             itemBuilder: (ctx, idx) {
//               final s = filtered[idx];
//               final itemKey = ValueKey("${s.path}_$idx");
//               final bool isPlaying = (s.path == currentPath);
//               // 1. 將 Listener 放在最外層，確保整個 ListTile 都能觸發計時器
//               return ReorderableDelayedDragStartListener(
//                 key: itemKey,
//                 index: idx,
//                 child: Listener(
//                   //放棄震動
//                   child: ListTile(
//                     tileColor: isPlaying
//                         ? Theme.of(
//                             context,
//                           ).colorScheme.primaryContainer.withValues(alpha: 0.5)
//                         : null,
//                     // 這裡不再需要包裹 Listener，避免手勢攔截
//                     leading: Transform.translate(
//                       offset: Offset(isPlaying ? -6.5 : 0, 0),
//                       child: Padding(
//                         padding: const EdgeInsets.all(8.0),
//                         child: isPlaying
//                             ? const Icon(
//                                 Icons.play_arrow_rounded,
//                                 color: Colors.orange,
//                                 size: 36,
//                               )
//                             : const Icon(Icons.menu),
//                       ),
//                     ),
//                     title: HighlightedText(
//                       text: s.fileName,
//                       query: query,
//                       style: TextStyle(
//                         fontWeight: isPlaying
//                             ? FontWeight.bold
//                             : FontWeight.normal,
//                         color: isPlaying
//                             ? Theme.of(context).colorScheme.primary
//                             : null,
//                       ),
//                     ),
//                     subtitle: Text(
//                       format(s.duration),
//                       style: const TextStyle(fontSize: 10),
//                     ),
//                     trailing: IconButton(
//                       icon: const Icon(Icons.close),
//                       onPressed: () {
//                         myConfirmDialog(
//                           title: "確認刪除",
//                           content: "確定要從佇列中移除「${s.fileName}」嗎？",
//                           onConfirm: () {
//                             onDelete(queue.indexOf(s));
//                             myToast("已從佇列移除", durationSeconds: 1.0);
//                           },
//                         );
//                       },
//                     ),
//                     onTap: () => onPlay(s.path),
//                   ),
//                 ),
//               );
//             },
//           ),
//         ),
//       ],
//     );
//   }
// }

// --- 2. 瀏覽頁面 ---
// class FileBrowserPage extends StatefulWidget {
//   final List<Song> allSongs; // 新增
//   final List<Song> currentQueue;
//   final bool isScanning; // 新增
//   final VoidCallback onScan; // 新增
//   final String query;
//   final String Function(Duration) format;
//   final Set<String> favorites;
//   final Function(String) onPlay;
//   final Function(String) onToggleFav;
//   final Function(List<Song>) onBatchAdd;
//   final Function(bool, int, String) onSelectionChanged;

//   const FileBrowserPage({
//     super.key,
//     required this.allSongs,
//     required this.currentQueue,
//     required this.isScanning,
//     required this.onScan,
//     required this.query,
//     required this.format,
//     required this.favorites,
//     required this.onPlay,
//     required this.onToggleFav,
//     required this.onBatchAdd,
//     required this.onSelectionChanged,
//   });

//   @override
//   State<FileBrowserPage> createState() => _FileBrowserPageState();
// }

// class _FileBrowserPageState extends State<FileBrowserPage>
//     with AutomaticKeepAliveClientMixin {
//   final Set<String> _selected = {};
//   List<String> get selectedPaths => _selected.toList();
//   bool _isMulti = false;

//   @override
//   bool get wantKeepAlive => true;

//   void _cancelSelection() {
//     setState(() {
//       _isMulti = false;
//       _selected.clear();
//     });
//     widget.onSelectionChanged(false, 0, "00:00");
//   }

//   void _performAdd() {
//     // 1. 找出被選中且「不在」目前佇列中的歌曲
//     final toAdd = widget.allSongs.where((s) {
//       bool isSelected = _selected.contains(s.path);
//       // 檢查路徑是否已經存在於佇列中
//       bool alreadyInQueue = widget.currentQueue.any(
//         (item) => item.path == s.path,
//       );
//       return isSelected && !alreadyInQueue;
//     }).toList();

//     // 2. 根據過濾結果執行動作
//     if (toAdd.isNotEmpty) {
//       widget.onBatchAdd(toAdd);
//       myToast("已加入 ${toAdd.length} 首新歌曲");
//     } else {
//       if (_selected.isNotEmpty) {
//         myToast("選中的歌曲已全部在佇列中");
//       }
//     }

//     _cancelSelection();
//   }

//   @override
//   Widget build(BuildContext context) {
//     super.build(context);
//     final filtered = widget.allSongs.where((s) {
//       return s.fileName.toLowerCase().contains(widget.query.toLowerCase());
//     }).toList();
//     final totalDuration = filtered.fold(Duration.zero, (p, s) {
//       return p + s.duration;
//     });

//     return Column(
//       children: [
//         SubHeader(
//           text: "本地音樂：${filtered.length} 首 (${widget.format(totalDuration)})",
//           // 如果未來想在這裡加按鈕（例如全選），可以放在 trailing 參數
//         ),
//         // 如果正在掃描，顯示進度條
//         if (widget.isScanning) const LinearProgressIndicator(),
//         Expanded(
//           child: widget.allSongs.isEmpty && !widget.isScanning
//               ? const Center(
//                   child: Text(
//                     "找不到音樂檔案(.mp3)",
//                     style: TextStyle(color: Colors.grey),
//                   ),
//                 )
//               : ListView.builder(
//                   itemCount: filtered.length,
//                   itemBuilder: (ctx, idx) {
//                     final s = filtered[idx];
//                     bool isChecked = _selected.contains(s.path);
//                     bool isFav = widget.favorites.contains(s.path);

//                     return ListTile(
//                       leading: _isMulti
//                           ? Checkbox(
//                               value: isChecked,
//                               onChanged: (v) {
//                                 setState(() {
//                                   if (v!) {
//                                     _selected.add(s.path);
//                                   } else {
//                                     _selected.remove(s.path);
//                                   }
//                                 });
//                                 _notify();
//                               },
//                             )
//                           : const Icon(Icons.music_note),
//                       title: HighlightedText(
//                         text: s.fileName,
//                         query: widget.query,
//                       ),
//                       subtitle: Text(
//                         widget.format(s.duration),
//                         style: const TextStyle(fontSize: 10),
//                       ),
//                       trailing: _isMulti
//                           ? null
//                           : IconButton(
//                               icon: Icon(
//                                 isFav ? Icons.favorite : Icons.favorite_border,
//                                 color: Colors.red,
//                               ),
//                               onPressed: () {
//                                 widget.onToggleFav(s.path);
//                               },
//                             ),
//                       onLongPress: () {
//                         setState(() {
//                           _isMulti = true;
//                           _selected.add(s.path);
//                         });
//                         _notify();
//                       },
//                       onTap: () {
//                         if (_isMulti) {
//                           setState(() {
//                             if (isChecked) {
//                               _selected.remove(s.path);
//                             } else {
//                               _selected.add(s.path);
//                             }
//                           });
//                           _notify();
//                         } else {
//                           widget.onPlay(s.path);
//                         }
//                       },
//                     );
//                   },
//                 ),
//         ),
//       ],
//     );
//   }

//   void _notify() {
//     final selectedSongs = widget.allSongs.where((s) {
//       return _selected.contains(s.path);
//     });
//     final total = selectedSongs.fold(Duration.zero, (p, s) {
//       return p + s.duration;
//     });
//     widget.onSelectionChanged(_isMulti, _selected.length, widget.format(total));
//   }
// }
*/
