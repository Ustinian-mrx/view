# Algorithm Interface

This app keeps the model implementation behind the Android native bridge. Flutter now passes the NCNN param/bin, class list, and preprocessing JSON into Android, and Android copies them to cache before initializing native code.

Current native status:

- `android/app/src/main/cpp/ncnn_jni.cpp` now runs the bundled NCNN YOLO-style model through `in0 -> out0`.
- The native path converts YUV420 camera frames to RGB, applies rotation correction, letterboxes to `inputSize`, decodes `out0` as YOLOv8-style `[4 + 80, 8400]`, applies NMS, and returns up to 3 app-level detections.
- Low-light and low-contrast frames are enhanced with native adaptive contrast before inference.
- COCO classes are mapped into the Flutter app classes: `person`, `vehicle`, traffic-light color states, and `obstacle`.
- The native path supplements model output with lightweight scene cues for `tactile_paving` and `stairs`, because the bundled COCO model does not directly contain those two classes.
- If NCNN initialization or extraction fails, the app keeps a brightness/texture fallback detector instead of crashing.
- `android/app/src/main/cpp/CMakeLists.txt` links NCNN when both files below exist:
  - `android/app/src/main/jniLibs/arm64-v8a/libncnn.so`
  - `android/app/src/main/cpp/ncnn/include/ncnn/net.h`
- The current Android build is limited to `arm64-v8a`.
- The current model is wired for 640 input and 8400 candidates. Keep the app-side input size at 640 unless a replacement model is exported with matching dynamic output support.

## Input

Flutter sends camera frames to Android through the `vision_guard/ncnn` method channel:

```text
method: detectYuv420
planes: [Y, U, V] byte arrays
width: camera frame width
height: camera frame height
rotation: camera sensor orientation in degrees
bytesPerRow: stride for each plane
bytesPerPixel: pixel stride for each plane
```

Kotlin forwards the same data to:

```cpp
nativeDetectYuv420(y, u, v, width, height, rotation, bytesPerRow, bytesPerPixel)
```

Expected native pipeline:

1. Convert YUV420 to RGB/RGBA.
2. Rotate according to `rotation`.
3. Resize or letterbox to `inputSize`.
4. Run YOLO with NCNN.
5. Decode output heads.
6. Apply confidence filtering and NMS.
7. Return normalized boxes.

## NCNN Drop-In Layout

Ask the algorithm side to provide files in this exact layout:

```text
android/app/src/main/jniLibs/arm64-v8a/libncnn.so
android/app/src/main/cpp/ncnn/include/ncnn/net.h
android/app/src/main/cpp/ncnn/include/ncnn/mat.h
```

After those files are present, CMake defines `VISION_GUARD_WITH_NCNN=1`. The current implementation expects input blob `in0` and output blob `out0`.

## Output

Return an array of `DetectionNative` from C++:

```kotlin
DetectionNative(
    className = "obstacle",
    score = 0.76f,
    left = 0.35f,
    top = 0.42f,
    width = 0.28f,
    height = 0.24f,
    distanceMeters = 1.6f,
    direction = "center",
    riskScore = 0.92f
)
```

Fields:

- `className`: one of `obstacle`, `tactile_paving`, `stairs`, `traffic_light_red`, `traffic_light_green`, `traffic_light_yellow`, `person`, `vehicle`.
- `score`: model confidence, `0.0` to `1.0`.
- `left/top/width/height`: normalized coordinates in preview space after rotation correction, `0.0` to `1.0`.
- `distanceMeters`: estimated distance. Use `-1` if the model cannot estimate distance.
- `direction`: one of `left`, `center`, `right`. Flutter uses this in speech alerts.
- `riskScore`: algorithm-side danger score, `0.0` to `1.0`. Flutter uses it to choose the primary alert when multiple objects are detected.

## Performance Target

For the 50 ms target, keep image conversion and inference fully native. Avoid sending RGB pixels back to Dart. Reuse `ncnn::Net`, input buffers, and output vectors between frames.
