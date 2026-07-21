import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/alert_service.dart';
import '../../core/app_settings.dart';
import '../../core/detection.dart';
import '../../core/ncnn_bridge.dart';
import '../settings/settings_page.dart';
import 'widgets/awareness_map.dart';
import 'widgets/detection_banner.dart';
import 'widgets/detection_overlay.dart';
import 'widgets/status_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _bridge = NcnnBridge();
  final _alerts = AlertService();

  CameraController? _camera;
  AppSettings _settings = AppSettings.defaults;
  DetectionFrame? _frame;
  bool _isReady = false;
  bool _isProcessing = false;
  bool _streaming = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _torchEnabled = false;
  bool _torchChangeInFlight = false;
  int _lowLightFrames = 0;
  int _normalLightFrames = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _bridge.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _boot();
    } else if (state == AppLifecycleState.inactive) {
      _stopCamera();
    }
  }

  // AI辅助生成：Codex.2026-04-28) 串联权限、模型初始化和相机启动流程。
  Future<void> _boot() async {
    setState(() {
      _error = null;
      _isReady = false;
    });
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      setState(() => _error = '需要相机权限才能运行实时辅助。');
      return;
    }

    try {
      _settings = await AppSettings.load();
      await _bridge.initialize(_settings);
      await _startCamera();
      if (!mounted) return;
      setState(() => _isReady = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '初始化失败：$error');
    }
  }

  Future<void> _startCamera() async {
    await _stopCamera();
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {
      // Some camera implementations do not expose focus/exposure controls.
    }
    await controller.startImageStream(_onCameraImage);
    _camera = controller;
    _streaming = true;
  }

  Future<void> _stopCamera() async {
    final controller = _camera;
    _camera = null;
    _streaming = false;
    if (controller == null) return;
    if (_torchEnabled) {
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Some devices do not allow changing torch state while stopping.
      }
      _torchEnabled = false;
    }
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
  }

  // AI辅助生成：Codex.2026-04-28) 对相机帧做节流并送入端侧检测通道。
  Future<void> _onCameraImage(CameraImage image) async {
    if (_isProcessing || !_streaming) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt).inMilliseconds < 120) return;
    _lastFrameAt = now;
    _isProcessing = true;
    try {
      unawaited(_updateTorchForLowLight(image));
      final camera = _camera?.description;
      final frame = await _bridge.detectCameraFrame(
        planes: image.planes.map((plane) => plane.bytes).toList(growable: false),
        width: image.width,
        height: image.height,
        rotation: camera?.sensorOrientation ?? 90,
        formatGroup: image.format.group.index,
        bytesPerRow:
            image.planes.map((plane) => plane.bytesPerRow).toList(growable: false),
        bytesPerPixel: image.planes
            .map((plane) => plane.bytesPerPixel ?? 1)
            .toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _frame = frame);
      unawaited(_alerts.speakFor(frame, _settings));
    } catch (_) {
      // Keep the preview responsive even if a single frame fails.
    } finally {
      _isProcessing = false;
    }
  }

  // AI辅助生成：Codex.2026-04-28) 根据画面亮度自动控制手电，提升低光场景可用性。
  Future<void> _updateTorchForLowLight(CameraImage image) async {
    final controller = _camera;
    if (controller == null || _torchChangeInFlight || image.planes.isEmpty) {
      return;
    }

    final brightness = _averageLuma(image);
    if (brightness < 20) {
      _lowLightFrames += 1;
      _normalLightFrames = 0;
    } else if (brightness > 35) {
      _normalLightFrames += 1;
      _lowLightFrames = 0;
    } else {
      _lowLightFrames = 0;
      _normalLightFrames = 0;
    }

    final shouldEnable = !_torchEnabled && _lowLightFrames >= 3;
    final shouldDisable = _torchEnabled && _normalLightFrames >= 6;
    if (!shouldEnable && !shouldDisable) return;

    _torchChangeInFlight = true;
    try {
      await controller.setFlashMode(
        shouldEnable ? FlashMode.torch : FlashMode.off,
      );
      _torchEnabled = shouldEnable;
      _lowLightFrames = 0;
      _normalLightFrames = 0;
    } catch (_) {
      _lowLightFrames = 0;
      _normalLightFrames = 0;
    } finally {
      _torchChangeInFlight = false;
    }
  }

  double _averageLuma(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return 255;

    final rowStride = plane.bytesPerRow;
    final width = image.width;
    final height = image.height;
    var sum = 0;
    var count = 0;
    for (var y = 0; y < height; y += 12) {
      final row = y * rowStride;
      for (var x = 0; x < width; x += 12) {
        final index = row + x;
        if (index >= 0 && index < bytes.length) {
          sum += bytes[index];
          count += 1;
        }
      }
    }
    if (count == 0) return 255;
    return sum / count;
  }

  // AI辅助生成：Codex.2026-04-28) 从设置页返回后同步运行参数并恢复相机流。
  Future<void> _openSettings() async {
    await _alerts.stop();
    await _stopCamera();
    if (!mounted) return;
    setState(() {
      _isReady = false;
      _frame = null;
    });
    await Navigator.of(context).pushNamed(SettingsPage.routeName);
    final settings = await AppSettings.load();
    await _bridge.updateSettings(settings);
    await _alerts.applySettings(settings);
    await _startCamera();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _isReady = true;
      _frame = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: const Text('离线视觉辅助'),
        ),
        actions: [
          Semantics(
            button: true,
            label: '设置',
            hint: '打开辅助设置页面',
            child: IconButton(
              tooltip: '设置',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? _ErrorState(message: _error!, onRetry: _boot)
            : !_isReady || camera == null || !camera.value.isInitialized
                ? const _LoadingState()
                : Semantics(
                    label: '实时检测视图',
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(camera),
                              DetectionOverlay(frame: _frame),
                              Align(
                                alignment: Alignment.topCenter,
                                child: DetectionBanner(frame: _frame),
                              ),
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: AwarenessMap(frame: _frame),
                              ),
                            ],
                          ),
                        ),
                        StatusPanel(frame: _frame, settings: _settings),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '正在启动相机和端侧推理',
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('正在启动相机和端侧推理'),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: '错误',
              child: const Icon(Icons.error_outline_rounded, size: 56),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(message, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 20),
            Semantics(
              button: true,
              label: '重试',
              hint: '重新初始化相机和检测',
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
