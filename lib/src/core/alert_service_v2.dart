import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_settings.dart';
import 'detection.dart';

// 优化版：智能语音播报服务，支持多目标、动态间隔和场景感知
class AlertServiceV2 {
  AlertServiceV2() {
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.55); // 稍微降低语速，提高清晰度
    _tts.setVolume(1);
  }

  static const _channel = MethodChannel('vision_guard/ncnn');

  final FlutterTts _tts = FlutterTts();
  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastMessage;
  int _consecutiveSameCount = 0; // 连续相同消息计数

  // 场景状态追踪
  bool _hasActiveTrafficLight = false;
  DateTime _lastTrafficLightAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> stop() async {
    await _tts.stop();
    _lastMessage = null;
    _consecutiveSameCount = 0;
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
      await _tts.stop();
      await _tts.speak('测试语音播报功能，前方有障碍物，请注意避让');
    }
  }

  // 优化版：智能语音播报，支持多目标合并和动态间隔
  Future<void> speakFor(DetectionFrame frame, AppSettings settings) async {
    if (!settings.voiceEnabled && !settings.vibrationEnabled) return;

    final message = _buildSmartMessage(frame);
    if (message == null) return;

    final now = DateTime.now();
    final interval = _calculateDynamicInterval(frame, settings);

    // 智能抑制逻辑
    if (message == _lastMessage) {
      _consecutiveSameCount++;
      // 连续相同消息：第2次播报后，间隔翻倍
      if (_consecutiveSameCount > 1) {
        final extraQuiet = Duration(
          milliseconds: settings.alertIntervalMs * (_consecutiveSameCount - 1),
        );
        if (now.difference(_lastAlertAt) < extraQuiet) {
          return;
        }
      } else if (now.difference(_lastAlertAt) < interval) {
        return;
      }
    } else {
      _consecutiveSameCount = 0;
      if (now.difference(_lastAlertAt) < interval) {
        return;
      }
    }

    _lastMessage = message;
    _lastAlertAt = now;

    // 震动提醒
    if (settings.vibrationEnabled && frame.risk.index >= RiskLevel.warning.index) {
      await _vibrate(strong: frame.risk == RiskLevel.danger);
    }

    // 语音播报
    if (settings.voiceEnabled) {
      await _tts.stop();
      await _tts.speak(message);
    }
  }

  // 智能构建播报消息，支持多目标合并
  String? _buildSmartMessage(DetectionFrame frame) {
    final detections = frame.detections;
    if (detections.isEmpty) return null;

    // 更新场景状态
    _updateSceneState(detections);

    // 策略1：单个高风险目标，直接播报
    if (detections.length == 1) {
      return _buildSingleTargetMessage(detections.first);
    }

    // 策略2：多个目标，按优先级排序并智能合并
    final sorted = [...detections]..sort((a, b) {
        final typeWeight = _priority(b.type).compareTo(_priority(a.type));
        if (typeWeight != 0) return typeWeight;
        return b.riskScore.compareTo(a.riskScore);
      });

    // 如果有红绿灯，优先播报红绿灯状态
    final trafficLights = sorted.where((d) =>
        d.type == DetectionClass.trafficLightRed ||
        d.type == DetectionClass.trafficLightYellow ||
        d.type == DetectionClass.trafficLightGreen).toList();
    if (trafficLights.isNotEmpty) {
      return _buildTrafficLightMessage(trafficLights.first);
    }

    // 如果有危险目标（障碍物、台阶），播报最近的
    final dangers = sorted.where((d) =>
        d.type == DetectionClass.obstacle ||
        d.type == DetectionClass.stairs).toList();
    if (dangers.isNotEmpty) {
      return _buildDangerMessage(dangers);
    }

    // 其他情况，播报优先级最高的
    return _buildSingleTargetMessage(sorted.first);
  }

  // 更新场景状态
  void _updateSceneState(List<Detection> detections) {
    final now = DateTime.now();
    final hasTrafficLight = detections.any((d) =>
        d.type == DetectionClass.trafficLightRed ||
        d.type == DetectionClass.trafficLightYellow ||
        d.type == DetectionClass.trafficLightGreen);

    if (hasTrafficLight) {
      _hasActiveTrafficLight = true;
      _lastTrafficLightAt = now;
    } else if (now.difference(_lastTrafficLightAt).inSeconds > 5) {
      _hasActiveTrafficLight = false;
    }
  }

  // 构建单目标播报消息
  String _buildSingleTargetMessage(Detection detection) {
    final direction = _enhancedDirectionLabel(detection.direction, detection.box);
    final distance = _naturalDistanceLabel(detection.distanceMeters);
    final confidence = _confidenceLabel(detection.score);

    return switch (detection.type) {
      DetectionClass.obstacle =>
        '$direction有障碍物$distance$confidence，请注意避让',
      DetectionClass.stairs =>
        '$direction有台阶$distance$confidence，请慢行',
      DetectionClass.trafficLightRed => '前方红灯，请等待',
      DetectionClass.trafficLightYellow => '前方黄灯，请注意',
      DetectionClass.trafficLightGreen => '前方绿灯，可以通行',
      DetectionClass.tactilePaving => '检测到盲道',
      DetectionClass.person => '$direction有行人$distance',
      DetectionClass.vehicle => '$direction有车辆$distance$confidence，请注意',
      DetectionClass.unknown => null,
    };
  }

  // 构建危险目标播报消息
  String _buildDangerMessage(List<Detection> dangers) {
    if (dangers.length == 1) {
      return _buildSingleTargetMessage(dangers.first);
    }

    // 多个危险目标：播报最近的，并提示还有其他
    final nearest = dangers.reduce((a, b) =>
        (a.distanceMeters ?? 10) < (b.distanceMeters ?? 10) ? a : b);
    final otherCount = dangers.length - 1;

    final direction = _enhancedDirectionLabel(nearest.direction, nearest.box);
    final distance = _naturalDistanceLabel(nearest.distanceMeters);
    final typeLabel = nearest.type == DetectionClass.obstacle ? '障碍物' : '台阶';

    if (nearest.type == DetectionClass.stairs) {
      return '$direction有台阶$distance，请慢行，还有$otherCount个障碍物';
    }
    return '$direction有$typeLabel$distance，请注意避让，还有$otherCount个危险目标';
  }

  // 构建红绿灯播报消息
  String _buildTrafficLightMessage(Detection trafficLight) {
    final distance = _naturalDistanceLabel(trafficLight.distanceMeters);

    return switch (trafficLight.type) {
      DetectionClass.trafficLightRed => '前方红灯$distance，请等待',
      DetectionClass.trafficLightYellow => '前方黄灯$distance，请注意',
      DetectionClass.trafficLightGreen => '前方绿灯$distance，可以通行',
      _ => '前方有交通灯$distance',
    };
  }

  // 增强的方向标签，考虑目标在画面中的位置
  String _enhancedDirectionLabel(ObjectDirection direction, Rect box) {
    // 根据目标在画面中的垂直位置调整方向表达
    final verticalCenter = box.top + box.height / 2;

    if (verticalCenter > 0.7) {
      // 目标在画面下方（靠近用户）
      return switch (direction) {
        ObjectDirection.left => '左前方近处',
        ObjectDirection.right => '右前方近处',
        ObjectDirection.center => '正前方近处',
        ObjectDirection.unknown => '近处',
      };
    } else if (verticalCenter < 0.3) {
      // 目标在画面上方（远离用户）
      return switch (direction) {
        ObjectDirection.left => '左前方远处',
        ObjectDirection.right => '右前方远处',
        ObjectDirection.center => '正前方远处',
        ObjectDirection.unknown => '远处',
      };
    }

    // 默认方向标签
    return direction.label;
  }

  // 自然的距离标签
  String _naturalDistanceLabel(double? distanceMeters) {
    if (distanceMeters == null || distanceMeters < 0) return '';

    if (distanceMeters < 1.0) {
      return '约${(distanceMeters * 100).round()}厘米';
    } else if (distanceMeters < 3.0) {
      return '约${distanceMeters.toStringAsFixed(1)}米';
    } else if (distanceMeters < 10.0) {
      return '约${distanceMeters.round()}米';
    } else {
      return '较远';
    }
  }

  // 置信度标签（仅对低置信度目标提示）
  String _confidenceLabel(double score) {
    if (score < 0.6) return '（不太确定）';
    return '';
  }

  // 动态计算播报间隔
  Duration _calculateDynamicInterval(DetectionFrame frame, AppSettings settings) {
    final baseInterval = Duration(milliseconds: settings.alertIntervalMs);

    // 根据风险等级调整间隔
    switch (frame.risk) {
      case RiskLevel.danger:
        // 危险目标：缩短间隔
        return baseInterval * 0.6;
      case RiskLevel.warning:
        // 警告目标：正常间隔
        return baseInterval;
      case RiskLevel.notice:
        // 注意目标：延长间隔
        return baseInterval * 1.5;
      case RiskLevel.safe:
        // 安全：大幅延长间隔
        return baseInterval * 2;
    }
  }

  int _priority(DetectionClass type) {
    return switch (type) {
      DetectionClass.trafficLightRed => 5,
      DetectionClass.stairs => 5,
      DetectionClass.obstacle => 4,
      DetectionClass.trafficLightYellow => 3,
      DetectionClass.vehicle => 3,
      DetectionClass.person => 2,
      DetectionClass.tactilePaving => 1,
      DetectionClass.trafficLightGreen => 1,
      DetectionClass.unknown => 0,
    };
  }

  Future<void> _vibrate({required bool strong}) async {
    await HapticFeedback.heavyImpact();
    await _channel.invokeMethod<void>('vibrateAlert', {'strong': strong});
  }
}
