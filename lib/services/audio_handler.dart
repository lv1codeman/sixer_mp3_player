import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer(); // 這是 just_audio 的播放器
  VoidCallback? onComplete;
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

  MyAudioHandler() {
    // 監聽播放狀態並傳遞給系統通知列
    // _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.playbackEventStream.map(_transformEvent).listen((state) {
      // 檢查是否已被關閉，避免 Bad state
      if (!playbackState.isClosed) {
        playbackState.add(state);
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        final position = _player.position;
        final duration = _player.duration ?? Duration.zero;
        if (position.inSeconds > 0 &&
            (duration.inSeconds - position.inSeconds).abs() < 2) {
          debugPrint("歌曲播放完畢，跳下一首");
          skipToNext();
        } else {
          debugPrint("偵測到異常完成狀態，停止播放避免連跳。Pos: $position, Dur: $duration");
          _player.stop();
        }
      }
    });
  }

  // 公開的 Getter
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> skipToNext() async {
    // 執行 UI 傳進來的下一首邏輯 (處理隨機或順序)
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipPrevious != null) {
      onSkipPrevious!();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    // 清除當前媒體資訊，防止 UI 繼續接收舊數據
    // mediaItem.add(null);
    await super.stop();
  }

  // 處理播放路徑與通知列資訊
  Future<void> playPath(String path) async {
    try {
      await _player.stop();

      // 解決 BAD_INDEX 的關鍵：增加極短的延遲，讓系統回收 c2.android.mp3.decoder
      await Future.delayed(const Duration(milliseconds: 200));

      // 使用 setFilePath 載入
      final duration = await _player.setFilePath(path);

      mediaItem.add(
        MediaItem(
          id: path,
          album: "SixerMP3",
          title: path.split('/').last,
          duration: duration,
        ),
      );

      _player.play();
      playbackState.add(_transformEvent(_player.playbackEvent));
    } catch (e) {
      debugPrint("Handler playPath Error: $e");
      // _isSwitchingTrack = false;
      // Future.delayed(const Duration(milliseconds: 500), () {
      // onSkipNext?.call();
      // });
    }
  }

  // 將 just_audio 的狀態轉換為系統通知列格式
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState:
          const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState] ??
          AudioProcessingState.idle,
      playing: _player.playing,
      updatePosition: _player.position,
      updateTime: DateTime.now(),
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }
}
