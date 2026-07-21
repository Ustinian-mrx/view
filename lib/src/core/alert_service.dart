import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_settings.dart';
import 'detection.dart';

// AI辅助生成：Codex.2026-04-28) 封装语音播报、震动和重复提醒抑制策略。
class AlertService {
  AlertService() {
    _ttsReady = _initializeTts();
  }

  static const _channel = MethodChannel('vision_guard/ncnn');

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _ttsReady;
  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastVibrationAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastMessage;
  int _repeatCount = 0;
  bool _isSpeaking = false;

  Future<void> _initializeTts() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.58);
    await _tts.setVolume(1);
    await _tts.setQueueMode(0);
    await _tts.setAudioAttributesForNavigation();
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
    _lastMessage = null;
    _repeatCount = 0;
  }

  Future<void> applySettings(AppSettings settings) async {
    if (!settings.voiceEnabled) {
      await stop();
    }
  }

  Future<void> test(AppSettings settings) async {
    if (settings.vibrationEnabled) {
      await _vibrate(strong: true);
    }
    if (settings.voiceEnabled) {
      await _speak('测试语音播报，前方有障碍物，请注意避让');
    }
  }

  // AI辅助生成：Codex.2026-04-28) 根据检测风险和用户设置触发语音/震动预警。
  Future<void> speakFor(DetectionFrame frame, AppSettings settings) async {
    final message = _messageFor(frame);
    if (message == null) return;

    final now = DateTime.now();
    final interval = _calcInterval(frame, settings);

    if (message == _lastMessage) {
      _repeatCount++;
      final effectiveInterval = interval * (1 + _repeatCount * 0.5);
      if (now.difference(_lastAlertAt) < effectiveInterval) return;
    } else {
      _repeatCount = 0;
      if (now.difference(_lastAlertAt) < interval) return;
    }

    _lastMessage = message;
    _lastAlertAt = now;

    if (settings.vibrationEnabled &&
        frame.risk.index >= RiskLevel.warning.index &&
        now.difference(_lastVibrationAt) >= const Duration(seconds: 3)) {
      _lastVibrationAt = now;
      await _vibrate(strong: frame.risk == RiskLevel.danger);
    }

    if (settings.voiceEnabled) {
      await _speak(message);
    }
  }

  Future<void> _speak(String message) async {
    if (_isSpeaking) return;
    _isSpeaking = true;
    try {
      await _ttsReady;
      await _tts.speak(message, focus: true);
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> _vibrate({required bool strong}) async {
    await _channel.invokeMethod<void>('vibrateAlert', {'strong': strong});
  }

  Duration _calcInterval(DetectionFrame frame, AppSettings settings) {
    final base = settings.alertIntervalMs;
    return switch (frame.risk) {
      RiskLevel.danger => Duration(milliseconds: (base * 0.7).round()),
      RiskLevel.warning => Duration(milliseconds: base),
      RiskLevel.notice => Duration(milliseconds: (base * 1.3).round()),
      RiskLevel.safe => Duration(milliseconds: (base * 1.8).round()),
    };
  }

  String? _messageFor(DetectionFrame frame) {
    final detections = frame.detections;
    if (detections.isEmpty) return null;

    if (detections.length == 1) {
      return _singleMessage(detections.first);
    }

    final dangers = detections
        .where((d) =>
            d.type == DetectionClass.obstacle ||
            d.type == DetectionClass.stairs ||
            d.type == DetectionClass.trafficLightRed)
        .toList();

    if (dangers.length > 1) {
      return _mergeDangerMessage(dangers);
    }

    return _singleMessage(detections.first);
  }

  String? _singleMessage(Detection d) {
    final dir = _dirLabel(d.direction, d.box);
    final dist = _distLabel(d.distanceMeters);

    switch (d.type) {
      case DetectionClass.obstacle:
        return '$dir有障碍物$dist，请注意避让';
      case DetectionClass.stairs:
        return '$dir有台阶$dist，请慢行';
      case DetectionClass.trafficLightRed:
        return '前方红灯$dist，请等待';
      case DetectionClass.trafficLightYellow:
        return '前方黄灯$dist，请注意';
      case DetectionClass.trafficLightGreen:
        return '前方绿灯$dist，可以通行';
      case DetectionClass.tactilePaving:
        return '检测到盲道';
      case DetectionClass.person:
        return '$dir有行人$dist';
      case DetectionClass.vehicle:
        return '$dir有车辆$dist，请注意';
      case DetectionClass.unknown:
        return null;
    }
  }

  String _mergeDangerMessage(List<Detection> dangers) {
    final nearest = dangers.reduce(
        (a, b) => (a.distanceMeters ?? 10) < (b.distanceMeters ?? 10) ? a : b);
    final otherCount = dangers.length - 1;
    final dir = _dirLabel(nearest.direction, nearest.box);
    final dist = _distLabel(nearest.distanceMeters);
    final type = nearest.type == DetectionClass.stairs ? '台阶' : '障碍物';

    return '$dir有$type$dist，请注意，还有$otherCount个危险目标';
  }

  String _dirLabel(ObjectDirection dir, Rect box) {
    final vy = box.top + box.height / 2;
    final prefix = switch (dir) {
      ObjectDirection.left => '左前方',
      ObjectDirection.right => '右前方',
      ObjectDirection.center => '正前方',
      ObjectDirection.unknown => '前方',
    };
    if (vy > 0.7) return '$prefix近处';
    if (vy < 0.3) return '$prefix远处';
    return prefix;
  }

  String _distLabel(double? meters) {
    if (meters == null || meters < 0) return '';
    if (meters < 1.0) return '约${(meters * 100).round()}厘米';
    if (meters < 3.0) return '约${meters.toStringAsFixed(1)}米';
    if (meters < 10.0) return '约${meters.round()}米';
    return '较远';
  }
}
