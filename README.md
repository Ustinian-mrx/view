# Vision Guard

离线实时视觉辅助 Flutter App，面向视障人士使用。前端负责相机预览、实时结果展示、语音/震动预警和运行设置；Android 原生侧通过方法通道对接 YOLO + NCNN 端侧推理。

## 功能范围

- Flutter UI：主检测页、设置页、高对比状态栏、检测框 Overlay。
- 相机输入：`camera` 插件获取 YUV420 帧，逐帧传给 Android 方法通道。
- 预警输出：`flutter_tts` 中文语音播报，`vibration` 高风险震动。
- 设置：语音、震动、置信度阈值、播报间隔、推理输入尺寸会立即影响运行链路。
- Android 原生：Kotlin `MethodChannel` + JNI `vision_ncnn`，当前 C++ 已接入 NCNN，执行 `in0 -> out0` 推理、YOLOv8 风格解码和 NMS；失败时保留亮度/纹理 fallback。
- 场景能力：在 COCO 模型输出基础上补充红绿灯颜色判断、盲道色块线索、台阶水平边缘线索和低光/低对比增强，使功能范围更贴合作品简介。

## 本地运行

1. 安装 Flutter SDK，并在 `android/local.properties` 写入：

   ```properties
   flutter.sdk=C:\\path\\to\\flutter
   ```

   如果不确定路径，可以复制 `android/local.properties.example` 后在 Android Studio 的 Flutter 设置页查看 SDK 路径。

2. 获取依赖：

   ```bash
   flutter pub get
   ```

3. 替换模型文件：

   ```text
   assets/models/yolo_blind_assist.param
   assets/models/yolo_blind_assist.bin
   ```

4. Android 真机运行：

   ```bash
   flutter run
   ```

## NCNN 对接方案

Flutter 调用入口在 `lib/src/core/ncnn_bridge.dart`，方法通道名为 `vision_guard/ncnn`。

Android 侧协议：

- `initialize`：复制 Flutter asset 中的 `.param/.bin` 到 cache，初始化 NCNN 网络。
- `updateSettings`：更新输入尺寸和置信度阈值。
- `detectYuv420`：接收三平面 YUV420、宽高、旋转、stride，返回检测列表。
- `dispose`：释放 native 资源。

返回数据格式：

```json
{
  "timestamp": 1710000000000,
  "latencyMs": 32,
  "detections": [
    {
      "class": "obstacle",
      "score": 0.76,
      "box": [0.35, 0.42, 0.28, 0.24],
      "distanceMeters": 1.6,
      "direction": "center",
      "riskScore": 0.92
    }
  ]
}
```

`box` 使用归一化 `[left, top, width, height]`，类别建议固定为：

- `obstacle`
- `tactile_paving`
- `stairs`
- `traffic_light_red`
- `traffic_light_green`
- `traffic_light_yellow`
- `person`
- `vehicle`

更细的算法接口说明见 `docs/algorithm_interface.md`。

## NCNN 运行库

当前工程已放入 arm64-v8a 的 NCNN shared 运行库：

```text
android/app/src/main/jniLibs/arm64-v8a/libncnn.so
android/app/src/main/cpp/ncnn/include/ncnn/*.h
```

如果以后要替换 NCNN 版本：

1. 将预编译 NCNN so 放入：

   ```text
   android/app/src/main/jniLibs/arm64-v8a/libncnn.so
   ```

2. 将对应 headers 放入 `android/app/src/main/cpp/ncnn/include/ncnn/`。

3. 确认 `android/app/src/main/cpp/ncnn_jni.cpp` 中的输入输出名仍然匹配模型：

   - input: `in0`
   - output: `out0`

当前模型按 640 输入和 8400 候选点接入。替换模型时，如果输出形状、类别数或 blob 名变化，需要同步修改 C++ 解码逻辑。

4. 50ms 目标建议：

   - 输入优先 `320` 或轻量 `416`。
   - 使用 `ResolutionPreset.low`，避免 Dart 侧做图像转换。
   - 原生侧复用 `ncnn::Net`、临时 buffer 和 extractor 参数。
   - 开启 Vulkan 需同时引入带 Vulkan 的 NCNN，并在初始化时按设备能力降级。

## 关键文件

- Flutter 入口：`lib/main.dart`
- 主页面：`lib/src/features/home/home_page.dart`
- 设置页：`lib/src/features/settings/settings_page.dart`
- 方法通道：`lib/src/core/ncnn_bridge.dart`
- Android 通道：`android/app/src/main/kotlin/com/example/vision_guard/MainActivity.kt`
- JNI 桥：`android/app/src/main/cpp/ncnn_jni.cpp`
