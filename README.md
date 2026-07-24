# Vision Guard（明行）

面向视障人士的 Android 离线实时视觉辅助应用。Flutter 负责相机预览、检测结果展示、语音/震动预警和运行设置；Android 原生层通过 Kotlin、JNI 和 NCNN 执行 YOLO26 目标检测。

## 当前能力

- 后置相机 YUV420 实时检测，全流程离线运行。
- 检测行人、骑行者、车辆、交通灯、交通标志和火车等 10 个训练类别。
- 将模型类别归并为 App 使用的 `person`、`vehicle`、`obstacle`，并通过图像规则判断交通灯颜色。
- 通过中文语音、震动、检测框、风险横幅和环境感知图提供提醒。
- 盲道与台阶目前为颜色/边缘规则辅助检测，并非 YOLO26 已训练类别，演示和评测时应明确区分。

> 本项目是辅助感知原型，检测结果可能出现漏检或误检，不能替代盲杖、导盲犬或专业导航设备。

## 技术结构

```text
Camera (YUV420)
  -> Flutter MethodChannel
  -> Kotlin
  -> JNI / NCNN (arm64-v8a)
  -> YOLO26 decode + NMS + rule-assisted detection
  -> Flutter overlay / TTS / vibration
```

主要技术：Flutter、Dart、Kotlin、C++、CMake、NCNN、YOLO26。

## 本地环境

项目当前只构建 Android `arm64-v8a`，需要使用 64 位 ARM Android 真机。建议使用以下环境：

- Windows 10/11。
- Flutter stable；当前验证版本为 Flutter `3.44.7`、Dart `3.12.2`。
- Android Studio 或独立 Android SDK，包含 Platform Tools、CMake 和 NDK。
- JDK 17。
- 支持 USB 调试的 arm64 Android 手机。

工程当前使用 Gradle `8.7`、Android Gradle Plugin `8.6.1` 和 Kotlin `2.1.0`。新版 Flutter 可能提示这些版本即将停止支持，这是升级提醒，不是本次构建失败；升级时需要成组验证 Gradle、AGP 和 Kotlin 的兼容性。

先检查基础环境：

```powershell
flutter doctor -v
java -version
adb version
```

## 首次配置

1. 克隆项目并进入目录：

   ```powershell
   git clone <repository-url> view
   cd view
   ```

2. 根据示例创建本机配置。不要提交生成的 `android/local.properties`：

   ```powershell
   Copy-Item android\local.properties.example android\local.properties
   ```

3. 编辑 `android/local.properties`，使用本机真实路径。Windows properties 文件中的反斜杠需要写成 `\\`：

   ```properties
   flutter.sdk=C:\\src\\flutter
   sdk.dir=C:\\Users\\your_name\\AppData\\Local\\Android\\Sdk
   ```

4. 获取 Flutter 依赖并检查设备：

   ```powershell
   flutter pub get
   adb devices
   flutter devices
   ```

   手机端需要开启“开发者选项”和“USB 调试”，并确认电脑弹出的调试授权。小米设备安装失败时，还需检查开发者选项中的“USB 安装”等系统限制。

## 运行与安装

开发调试：

```powershell
flutter run
```

真机性能测试应使用 Release，Debug 模式的帧率和延迟不能代表实际性能：

```powershell
flutter run --release
```

单独构建并安装 APK：

```powershell
flutter build apk --release --target-platform android-arm64
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

生成文件位于 `build\app\outputs\flutter-apk\app-release.apk`。首次启动需要允许相机权限；语音预警还依赖手机中可用的中文 TTS 引擎及其语音数据。

当前 `release` 构建为方便本地真机测试，暂时使用 Android Debug 签名。它不适合应用商店或正式分发，正式发布前必须创建并妥善保管独立 keystore，再通过本机私有配置接入 Release signing。

## NCNN 模型配置

运行所需文件均已纳入工程：

```text
assets/models/yolo_blind_assist.param
assets/models/yolo_blind_assist.bin
assets/models/classes.txt
assets/models/preprocess.json
android/app/src/main/jniLibs/arm64-v8a/libncnn.so
android/app/src/main/cpp/ncnn/include/ncnn/
```

当前导出的 NCNN 模型约定为：

- 输入 blob：`in0`。
- 输出 blob：`out0`。
- 输入尺寸：`640 x 640`，RGB、letterbox、归一化到 `0-1`。
- 输出形状：`[1, 14, 8400]`，即 4 个框参数、10 个类别分数和 8400 个候选框。
- 输出不是端到端 `[1, 300, 6]`；App 在 C++ 中执行阈值筛选和 NMS。
- 默认置信度阈值 `0.25`，NMS IoU 阈值 `0.7`，最大检测数 `300`。

10 个模型类别的顺序必须与 `assets/models/classes.txt` 完全一致：

```text
person, rider, car, bus, truck, bike, motor,
traffic light, traffic sign, train
```

App 映射关系：`person -> person`；`rider/car/bus/truck/bike/motor/train -> vehicle`；`traffic light ->` 红/黄/绿灯规则分类；`traffic sign -> obstacle`。盲道 `tactile_paving` 和台阶 `stairs` 由额外规则产生。

### 替换模型

将 Ultralytics 导出的 `model.ncnn.param` 和 `model.ncnn.bin` 分别覆盖为：

```text
assets/models/yolo_blind_assist.param
assets/models/yolo_blind_assist.bin
```

然后依次确认：

1. `classes.txt` 的数量、顺序与训练数据一致。
2. `preprocess.json` 与导出时的输入尺寸和预处理一致。
3. 模型 blob 仍为 `in0 -> out0`。
4. 输出仍为 4 个框通道加类别通道；类别数或输出布局变化时，同步修改 `android/app/src/main/cpp/ncnn_jni.cpp`。
5. 执行一次干净重建，防止 APK 继续携带旧 asset：

   ```powershell
   flutter clean
   flutter pub get
   flutter run --release
   ```

## 配置与数据协议

Flutter 调用入口为 `lib/src/core/ncnn_bridge.dart`，方法通道名为 `vision_guard/ncnn`：

- `initialize`：将模型 asset 复制到应用缓存并初始化 NCNN。
- `updateSettings`：同步输入尺寸和置信度阈值。
- `detectYuv420`：传入相机三平面、尺寸、旋转和 stride，返回检测结果。
- `dispose`：释放原生资源。

单个检测结果示例：

```json
{
  "class": "vehicle",
  "score": 0.76,
  "box": [0.35, 0.42, 0.28, 0.24],
  "distanceMeters": 1.6,
  "direction": "center",
  "riskScore": 0.92
}
```

`box` 为归一化的 `[left, top, width, height]`。更完整的协议见 `docs/algorithm_interface.md`。

## 验证

提交前建议执行：

```powershell
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

目前 `lib/src/core/alert_service_v2.dart` 是未接入主流程的实验文件，并存在静态分析问题，因此 `flutter analyze` 尚不能作为全绿基线。不要为绕过该问题而忽略整个 `lib/`；应在后续明确保留或删除实验实现后单独修复。

真机验收至少记录 Release 模式下连续 100 帧的平均值、P50、P95、检测 FPS，并进行 15 至 30 分钟稳定性测试。模型效果应使用独立测试集报告各类别 Precision、Recall、mAP 和典型误检/漏检，不应仅展示训练集或验证集结果。

## 常见问题

- `INSTALL_PARSE_FAILED_NO_CERTIFICATES`：先重新执行 `flutter clean` 和 Release 构建，确认 APK 使用有效签名；必要时卸载手机上的旧包后再安装。
- 找不到 Flutter SDK：检查 `android/local.properties` 中的 `flutter.sdk`，不要只配置系统 `PATH`。
- 找不到 Android SDK：检查 `sdk.dir`，并运行 `flutter doctor -v` 查看缺失组件。
- 设备未显示：运行 `adb kill-server`、`adb start-server`，重新插拔数据线并确认手机授权。
- 模型初始化失败：检查四个模型 asset 是否存在、`pubspec.yaml` 是否声明它们，以及 `.param/.bin` 是否来自同一次导出。
- Debug 模式卡顿：改用 `flutter run --release` 后再测；当前链路仍包含 Dart 到 Kotlin/JNI 的帧复制，性能数据需以真机实测为准。

## 目录说明

```text
lib/                         Flutter 页面、状态与提醒逻辑
assets/models/               NCNN 模型、类别和预处理配置
android/app/src/main/kotlin/ Android 方法通道与原生引擎封装
android/app/src/main/cpp/    JNI、NCNN 解码和规则辅助检测
docs/                        算法接口与专项说明
release/                     交付说明和人工发布产物
third_party/                 工程内固定的 Flutter 插件源码依赖
```

关键入口：

- `lib/main.dart`：Flutter 入口。
- `lib/src/features/home/home_page.dart`：相机与检测主页面。
- `lib/src/core/alert_service.dart`：语音和震动提醒。
- `lib/src/core/ncnn_bridge.dart`：Flutter 方法通道。
- `android/app/src/main/kotlin/com/example/vision_guard/MainActivity.kt`：Android 通道入口。
- `android/app/src/main/cpp/ncnn_jni.cpp`：NCNN 推理、解码和规则检测。
