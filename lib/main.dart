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

// --- 歌曲資訊模型 ---
class Song {
  final String path;
  final Duration duration;
  Song({required this.path, required this.duration});

  String get fileName {
    return path.split('/').last;
  }
}

class SixerMP3Player extends StatelessWidget {
  const SixerMP3Player({super.key});

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
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

// --- 關鍵字高亮顯示 ---
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
  const MainScreen({super.key});
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
  int _playMode = 0; // 0: 列表循環, 1: 單曲, 2: 隨機

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
    await _audioPlayer.play(DeviceFileSource(path));
    setState(() {
      _currentPath = path;
      _currentTitle = path.split('/').last;
    });
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    bool isBrowser = (_selectedIndex == 1);
    bool isPlaylistPage = (_selectedIndex == 3);

    return Scaffold(
      appBar: AppBar(
        title: const Text("SixerMP3"),
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
          if (isBrowser) ...{
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
          if (_isSearching) ...{
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: "搜尋音樂..."),
                onChanged: (v) {
                  setState(() {});
                },
              ),
            ),
          },
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
                ),
                FileBrowserPage(
                  key: _fileBrowserKey,
                  query: _searchController.text,
                  format: _formatDuration,
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
                PlaylistPage(playlists: _playlists),
              ],
            ),
          ),
          const Divider(height: 1),
          if (!isPlaylistPage) ...{
            _isMultiSelectMode
                ? Container(
                    padding: const EdgeInsets.all(12),
                    color: colorScheme.primaryContainer,
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle),
                        const SizedBox(width: 8),
                        Text(
                          "已選 $_selectedCount 首",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "($_selectedTotalTime)",
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () {
                            _fileBrowserKey.currentState?._performAdd();
                          },
                          child: const Text("加入"),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _fileBrowserKey.currentState?._cancelSelection();
                          },
                        ),
                      ],
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Column(
                      children: [
                        Text(
                          _currentTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                        ),
                        Slider(
                          value: _position.inSeconds.toDouble(),
                          max: _duration.inSeconds.toDouble() > 0
                              ? _duration.inSeconds.toDouble()
                              : 1.0,
                          onChanged: (v) {
                            _audioPlayer.seek(Duration(seconds: v.toInt()));
                          },
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
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
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
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: '佇列'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_open), label: '瀏覽'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: '收藏'),
          BottomNavigationBarItem(icon: Icon(Icons.playlist_play), label: '清單'),
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

  const QueuePage({
    super.key,
    required this.queue,
    required this.currentPath,
    required this.query,
    required this.format,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = queue.where((s) {
      return s.fileName.toLowerCase().contains(query.toLowerCase());
    }).toList();
    final totalDuration = filtered.fold(Duration.zero, (p, s) {
      return p + s.duration;
    });

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.black12,
          child: Text(
            "佇列：${filtered.length} 首 (${format(totalDuration)})",
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, idx) {
              final s = filtered[idx];
              return ListTile(
                selected: (s.path == currentPath),
                title: HighlightedText(text: s.fileName, query: query),
                trailing: Text(
                  format(s.duration),
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  onPlay(s.path);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- 2. 瀏覽頁面 ---
class FileBrowserPage extends StatefulWidget {
  final String query;
  final String Function(Duration) format;
  final Function(List<Song>) onBatchAdd;
  final Function(bool, int, String) onSelectionChanged;

  const FileBrowserPage({
    super.key,
    required this.query,
    required this.format,
    required this.onBatchAdd,
    required this.onSelectionChanged,
  });

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<Song> _allSongs = [];
  final Set<String> _selected = {};
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
            in root
                .list(recursive: true, followLinks: false)
                .handleError((e) {})) {
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
            } catch (e) {}

            if (mounted) {
              setState(() {
                _allSongs.add(Song(path: entity.path, duration: d));
              });
            }
          }
        }
      } catch (e) {}
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
        if (_isScanning) ...{const LinearProgressIndicator()},
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.black12,
          child: Text(
            "本地音樂：${filtered.length} 首 (${widget.format(totalDuration)})",
            style: const TextStyle(fontSize: 12),
          ),
        ),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.black12,
          child: Text(
            "收藏：${list.length} 首",
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (ctx, idx) {
              return ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: HighlightedText(
                  text: list[idx].split('/').last,
                  query: query,
                ),
                onTap: () {
                  onPlay(list[idx]);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    onToggle(list[idx]);
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
  const PlaylistPage({super.key, required this.playlists});

  @override
  Widget build(BuildContext context) {
    final names = playlists.keys.toList();
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (ctx, idx) {
        return ListTile(
          leading: const Icon(Icons.playlist_play),
          title: Text(names[idx]),
          subtitle: Text("共 ${playlists[names[idx]]!.length} 首歌曲"),
        );
      },
    );
  }
}
