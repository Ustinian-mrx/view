import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'detection.dart';

class NcnnBridge {
  // AI辅助生成：Codex.2026-04-28) 封装 Flutter 与 Android 原生 NCNN 推理通道。
  static const _channel = MethodChannel('vision_guard/ncnn');

  Future<void> initialize(AppSettings settings) {
    return _channel.invokeMethod<void>('initialize', {
      'paramAsset': 'assets/models/yolo_blind_assist.param',
      'binAsset': 'assets/models/yolo_blind_assist.bin',
      'classesAsset': 'assets/models/classes.txt',
      'preprocessAsset': 'assets/models/preprocess.json',
      'inputSize': settings.inputSize,
      'confidenceThreshold': settings.confidenceThreshold,
    });
  }

  // AI辅助生成：Codex.2026-03-28) 将阈值和输入尺寸变化同步到原生推理层。
  Future<void> updateSettings(AppSettings settings) {
    return _channel.invokeMethod<void>('updateSettings', {
      'inputSize': settings.inputSize,
      'confidenceThreshold': settings.confidenceThreshold,
    });
  }

  // AI辅助生成：Codex.2026-03-30) 将 YUV420 相机帧打包传入 Android 原生检测入口。
  Future<DetectionFrame> detectCameraFrame({
    required List<Uint8List> planes,
    required int width,
    required int height,
    required int rotation,
    required int formatGroup,
    required List<int> bytesPerRow,
    required List<int> bytesPerPixel,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'detectYuv420',
      {
        'planes': planes,
        'width': width,
        'height': height,
        'rotation': rotation,
        'formatGroup': formatGroup,
        'bytesPerRow': bytesPerRow,
        'bytesPerPixel': bytesPerPixel,
      },
    );
    return DetectionFrame.fromMap(result ?? const {});
  }

  Future<void> dispose() => _channel.invokeMethod<void>('dispose');
}
