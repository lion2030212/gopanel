import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class AdminChatAudio {
  static final AudioPlayer _sentPlayer = AudioPlayer();
  static final AudioPlayer _receivedPlayer = AudioPlayer();
  static final List<String> _playedReceivedMessageIds = [];

  static Future<void> playSent() => _play(_sentPlayer, 'audio/sent.mp3');

  static Future<void> playReceived({Object? messageId}) {
    final id = messageId?.toString();
    if (id != null && _playedReceivedMessageIds.contains(id)) {
      return Future<void>.value();
    }
    if (id != null) {
      _playedReceivedMessageIds.add(id);
      if (_playedReceivedMessageIds.length > 100) {
        _playedReceivedMessageIds.removeAt(0);
      }
    }
    return _play(_receivedPlayer, 'audio/receive.mp3');
  }

  static Future<void> _play(AudioPlayer player, String asset) async {
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (error) {
      debugPrint('تعذر تشغيل صوت المحادثة: $error');
    }
  }
}
