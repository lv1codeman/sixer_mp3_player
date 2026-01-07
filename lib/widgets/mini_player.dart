import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

class MiniPlayer extends StatelessWidget {
  final String currentTitle;
  final String currentPath;
  final bool isPlaying;
  final int playMode;
  final Duration position;
  final Duration duration;
  final Set<String> favorites;
  final AudioHandler audioHandler; // 傳入 Handler 處理直接控制
  final String Function(Duration) formatDuration;
  final Stream<Duration> positionStream;

  // 回呼函數
  final Function(String) onToggleFav;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlay;
  final VoidCallback onTogglePlayMode;
  final Function(bool) onDraggingChanged;

  const MiniPlayer({
    super.key,
    required this.currentTitle,
    required this.currentPath,
    required this.isPlaying,
    required this.playMode,
    required this.position,
    required this.duration,
    required this.favorites,
    required this.audioHandler,
    required this.formatDuration,
    required this.positionStream,
    required this.onToggleFav,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlay,
    required this.onTogglePlayMode,
    required this.onDraggingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 曲目名稱
          Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: Text(
              currentTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 2. 進度條區塊
          _buildProgressSlider(context),

          // 3. 控制按鈕列
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 收藏按鈕
              IconButton(
                icon: Icon(
                  favorites.contains(currentPath)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: Colors.red,
                ),
                iconSize: 28,
                onPressed: () {
                  onToggleFav(currentPath); // 確保傳入目前路徑
                },
              ),
              // 上一首
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: onPrevious,
                iconSize: 40,
              ),
              // 播放暫停
              IconButton(
                icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
                iconSize: 64,
                color: colorScheme.primary,
                onPressed: onTogglePlay,
              ),
              // 下一首
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: onNext,
                iconSize: 40,
              ),
              // 播放模式
              IconButton(
                icon: Icon(_getPlayModeIcon()),
                iconSize: 28,
                onPressed: onTogglePlayMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 內部私有方法：建立進度條
  Widget _buildProgressSlider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: StreamBuilder<Duration>(
        stream: positionStream,
        builder: (context, snapshot) {
          final currentPos = snapshot.data ?? position;

          return Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  formatDuration(currentPos),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Expanded(
                child: Slider(
                  activeColor: Theme.of(context).colorScheme.primary,
                  value: currentPos.inSeconds.toDouble().clamp(
                    0.0,
                    duration.inSeconds.toDouble() > 0
                        ? duration.inSeconds.toDouble()
                        : 0.0,
                  ),
                  min: 0.0,
                  max: duration.inSeconds.toDouble() > 0
                      ? duration.inSeconds.toDouble()
                      : 0.0,
                  onChangeStart: (_) => onDraggingChanged(true),
                  onChanged: (value) {
                    // 這裡通常會交給父組件更新 UI 或直接 seek
                  },
                  onChangeEnd: (value) async {
                    await audioHandler.seek(Duration(seconds: value.toInt()));
                    onDraggingChanged(false);
                  },
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  formatDuration(duration),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getPlayModeIcon() {
    if (playMode == 0) {
      return Icons.repeat;
    }
    if (playMode == 1) {
      return Icons.repeat_one;
    }
    return Icons.shuffle;
  }
}
