import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 集中管理短音效，避免多個畫面各自 new [AudioPlayer]。
///
/// iOS 對同時存在的 [AVPlayer] 數量有限制，多個畫面各持一個播放器時
/// 容易出現 `DarwinAudioError` / `AVPlayerItem.Status.failed`。
class AppSoundPlayer {
  AppSoundPlayer._();

  static final AppSoundPlayer instance = AppSoundPlayer._();

  final AudioPlayer _chatNotification = AudioPlayer();
  final AudioPlayer _carArrival = AudioPlayer();

  Future<void> playChatNotification() async {
    try {
      await _chatNotification.stop();
      await _chatNotification.play(AssetSource('chat_sound.mp3'));
    } catch (e) {
      debugPrint('播放聊天提示音失敗: $e');
    }
  }

  Future<void> playCarArrival() async {
    try {
      await _carArrival.stop();
      await _carArrival.play(AssetSource('get_car_sound.mp3'));
    } catch (e) {
      debugPrint('播放派車音效失敗: $e');
    }
  }
}
