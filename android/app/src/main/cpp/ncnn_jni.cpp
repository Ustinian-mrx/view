#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

#if VISION_GUARD_WITH_NCNN
#include <ncnn/net.h>
#endif

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VisionNCNN", __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, "VisionNCNN", __VA_ARGS__)

namespace {
float g_threshold = 0.45f;
int g_input_size = 320;
std::vector<std::string> g_classes;

#if VISION_GUARD_WITH_NCNN
ncnn::Net g_net;
bool g_ncnn_ready = false;
#else
bool g_ncnn_ready = false;
#endif

struct RegionStats {
    float mean;
    float variance;
    float dark_ratio;
};

struct RegionCandidate {
    const char* direction;
    float left;
    float top;
    float right;
    float bottom;
};

struct NativeDetection {
    std::string class_name;
    float score;
    float left;
    float top;
    float width;
    float height;
    float distance;
    const char* direction;
    float risk;
};

struct LetterboxInfo {
    int rotated_width;
    int rotated_height;
    float scale;
    float pad_x;
    float pad_y;
};

std::string read_file(const char* path) {
    std::ifstream input(path);
    if (!input) return "";
    return std::string((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
}

void load_classes(const char* classes_path) {
    g_classes.clear();
    std::ifstream input(classes_path);
    std::string line;
    while (std::getline(input, line)) {
        if (line.empty()) continue;
        const auto tab = line.find('\t');
        g_classes.push_back(tab == std::string::npos ? line : line.substr(tab + 1));
    }
}

RegionStats sample_region(const uint8_t* y_plane,
                          int width,
                          int height,
                          int row_stride,
                          float left_ratio,
                          float top_ratio,
                          float right_ratio,
                          float bottom_ratio,
                          bool skip_center) {
    const int left = std::clamp(static_cast<int>(width * left_ratio), 0, std::max(0, width - 1));
    const int right = std::clamp(static_cast<int>(width * right_ratio), left + 1, width);
    const int top = std::clamp(static_cast<int>(height * top_ratio), 0, std::max(0, height - 1));
    const int bottom = std::clamp(static_cast<int>(height * bottom_ratio), top + 1, height);
    const int center_left = static_cast<int>(width * 0.30f);
    const int center_right = static_cast<int>(width * 0.70f);

    int count = 0;
    double sum = 0.0;
    double sum_sq = 0.0;
    int dark = 0;
    for (int y = top; y < bottom; y += 4) {
        const int row = y * row_stride;
        for (int x = left; x < right; x += 4) {
            if (skip_center && x >= center_left && x <= center_right) continue;
            const int value = y_plane[row + x];
            sum += value;
            sum_sq += value * value;
            if (value < 82) dark += 1;
            count += 1;
        }
    }
    if (count == 0) return {0.0f, 0.0f, 0.0f};
    const float mean = static_cast<float>(sum / count);
    const float variance = static_cast<float>(sum_sq / count - mean * mean);
    return {mean, variance, static_cast<float>(dark) / count};
}

jobject make_detection(JNIEnv* env,
                       const char* class_name,
                       float score,
                       float left,
                       float top,
                       float width,
                       float height,
                       float distance,
                       const char* direction,
                       float risk_score) {
    jclass cls = env->FindClass("com/example/vision_guard/DetectionNative");
    if (cls == nullptr) return nullptr;
    jmethodID ctor = env->GetMethodID(
        cls, "<init>", "(Ljava/lang/String;FFFFFFLjava/lang/String;F)V");
    if (ctor == nullptr) {
        env->DeleteLocalRef(cls);
        return nullptr;
    }
    jstring name = env->NewStringUTF(class_name);
    jstring direction_name = env->NewStringUTF(direction);
    jobject detection = env->NewObject(
        cls, ctor, name, score, left, top, width, height, distance, direction_name, risk_score);
    env->DeleteLocalRef(name);
    env->DeleteLocalRef(direction_name);
    return detection;
}

uint8_t clamp_byte(float value) {
    return static_cast<uint8_t>(std::clamp(value, 0.0f, 255.0f));
}

int safe_plane_index(int x,
                     int y,
                     int row_stride,
                     int pixel_stride,
                     int plane_length) {
    const int index = y * row_stride + x * std::max(1, pixel_stride);
    return index >= 0 && index < plane_length ? index : -1;
}

// AI辅助生成：Codex.2026-04-20) 将相机 YUV420 数据按传感器方向转换为 RGB 图像。
std::vector<uint8_t> yuv420_to_rotated_rgb(const uint8_t* y_plane,
                                           const uint8_t* u_plane,
                                           const uint8_t* v_plane,
                                           int y_length,
                                           int u_length,
                                           int v_length,
                                           int width,
                                           int height,
                                           int rotation,
                                           const int* row_strides,
                                           int row_stride_count,
                                           const int* pixel_strides,
                                           int pixel_stride_count,
                                           int& rotated_width,
                                           int& rotated_height) {
    const int normalized_rotation = ((rotation % 360) + 360) % 360;
    const bool swap_size = normalized_rotation == 90 || normalized_rotation == 270;
    rotated_width = swap_size ? height : width;
    rotated_height = swap_size ? width : height;

    const int y_row_stride = row_stride_count > 0 && row_strides[0] > 0 ? row_strides[0] : width;
    const int u_row_stride = row_stride_count > 1 && row_strides[1] > 0 ? row_strides[1] : width / 2;
    const int v_row_stride = row_stride_count > 2 && row_strides[2] > 0 ? row_strides[2] : u_row_stride;
    const int u_pixel_stride =
        pixel_stride_count > 1 && pixel_strides[1] > 0 ? pixel_strides[1] : 1;
    const int v_pixel_stride =
        pixel_stride_count > 2 && pixel_strides[2] > 0 ? pixel_strides[2] : u_pixel_stride;

    std::vector<uint8_t> rgb(static_cast<size_t>(rotated_width) * rotated_height * 3);
    for (int dy = 0; dy < rotated_height; ++dy) {
        for (int dx = 0; dx < rotated_width; ++dx) {
            int sx = dx;
            int sy = dy;
            if (normalized_rotation == 90) {
                sx = dy;
                sy = height - 1 - dx;
            } else if (normalized_rotation == 180) {
                sx = width - 1 - dx;
                sy = height - 1 - dy;
            } else if (normalized_rotation == 270) {
                sx = width - 1 - dy;
                sy = dx;
            }

            const int y_index = sy * y_row_stride + sx;
            if (y_index < 0 || y_index >= y_length) continue;

            const int uv_x = std::clamp(sx / 2, 0, std::max(0, width / 2 - 1));
            const int uv_y = std::clamp(sy / 2, 0, std::max(0, height / 2 - 1));
            const int u_index =
                safe_plane_index(uv_x, uv_y, u_row_stride, u_pixel_stride, u_length);
            const int v_index =
                safe_plane_index(uv_x, uv_y, v_row_stride, v_pixel_stride, v_length);

            const float y_value = static_cast<float>(y_plane[y_index]);
            const float u_value = u_index >= 0 ? static_cast<float>(u_plane[u_index]) - 128.0f : 0.0f;
            const float v_value = v_index >= 0 ? static_cast<float>(v_plane[v_index]) - 128.0f : 0.0f;
            const size_t output = (static_cast<size_t>(dy) * rotated_width + dx) * 3;
            rgb[output] = clamp_byte(y_value + 1.402f * v_value);
            rgb[output + 1] = clamp_byte(y_value - 0.344136f * u_value - 0.714136f * v_value);
            rgb[output + 2] = clamp_byte(y_value + 1.772f * u_value);
        }
    }
    return rgb;
}

// AI辅助生成：Codex.2026-04-21) 按模型输入尺寸进行等比缩放和 letterbox 填充。
std::vector<uint8_t> letterbox_rgb(const std::vector<uint8_t>& source,
                                   int source_width,
                                   int source_height,
                                   int target_size,
                                   LetterboxInfo& info) {
    info.rotated_width = source_width;
    info.rotated_height = source_height;
    info.scale = std::min(
        static_cast<float>(target_size) / std::max(1, source_width),
        static_cast<float>(target_size) / std::max(1, source_height));
    const int resized_width =
        std::max(1, static_cast<int>(std::round(source_width * info.scale)));
    const int resized_height =
        std::max(1, static_cast<int>(std::round(source_height * info.scale)));
    const int pad_x = (target_size - resized_width) / 2;
    const int pad_y = (target_size - resized_height) / 2;
    info.pad_x = static_cast<float>(pad_x);
    info.pad_y = static_cast<float>(pad_y);

    std::vector<uint8_t> canvas(static_cast<size_t>(target_size) * target_size * 3, 114);
    for (int y = 0; y < resized_height; ++y) {
        const int sy = std::clamp(
            static_cast<int>(y / info.scale), 0, std::max(0, source_height - 1));
        for (int x = 0; x < resized_width; ++x) {
            const int sx = std::clamp(
                static_cast<int>(x / info.scale), 0, std::max(0, source_width - 1));
            const size_t src = (static_cast<size_t>(sy) * source_width + sx) * 3;
            const size_t dst =
                (static_cast<size_t>(y + pad_y) * target_size + x + pad_x) * 3;
            canvas[dst] = source[src];
            canvas[dst + 1] = source[src + 1];
            canvas[dst + 2] = source[src + 2];
        }
    }
    return canvas;
}

// AI辅助生成：Codex.2026-04-28) 对低光或低对比帧做轻量自适应增强。
void apply_adaptive_contrast(std::vector<uint8_t>& rgb) {
    if (rgb.empty()) return;

    int histogram[256] = {};
    const int pixel_count = static_cast<int>(rgb.size() / 3);
    for (int i = 0; i < pixel_count; i += 3) {
        const size_t offset = static_cast<size_t>(i) * 3;
        const int luma = static_cast<int>(
            0.299f * rgb[offset] + 0.587f * rgb[offset + 1] + 0.114f * rgb[offset + 2]);
        histogram[std::clamp(luma, 0, 255)] += 1;
    }

    const int sampled_count = (pixel_count + 2) / 3;
    const int low_target = std::max(1, sampled_count / 20);
    const int high_target = std::max(1, sampled_count * 19 / 20);
    int cumulative = 0;
    int low = 0;
    int high = 255;
    for (int i = 0; i < 256; ++i) {
        cumulative += histogram[i];
        if (cumulative >= low_target) {
            low = i;
            break;
        }
    }
    cumulative = 0;
    for (int i = 0; i < 256; ++i) {
        cumulative += histogram[i];
        if (cumulative >= high_target) {
            high = i;
            break;
        }
    }
    if (high - low >= 160 && low > 35) return;

    const float scale = 255.0f / std::max(40, high - low);
    for (uint8_t& value : rgb) {
        value = clamp_byte((static_cast<float>(value) - low) * scale);
    }
}

const char* direction_for_center(float center_x) {
    return center_x < 0.38f ? "left" : center_x > 0.62f ? "right" : "center";
}

float detection_iou(const NativeDetection& a, const NativeDetection& b) {
    const float a_right = a.left + a.width;
    const float a_bottom = a.top + a.height;
    const float b_right = b.left + b.width;
    const float b_bottom = b.top + b.height;
    const float inter_left = std::max(a.left, b.left);
    const float inter_top = std::max(a.top, b.top);
    const float inter_right = std::min(a_right, b_right);
    const float inter_bottom = std::min(a_bottom, b_bottom);
    const float inter_width = std::max(0.0f, inter_right - inter_left);
    const float inter_height = std::max(0.0f, inter_bottom - inter_top);
    const float inter_area = inter_width * inter_height;
    const float union_area = a.width * a.height + b.width * b.height - inter_area;
    return union_area <= 0.0f ? 0.0f : inter_area / union_area;
}

// AI辅助生成：Codex.2026-04-23) 在交通灯检测框内统计颜色，区分红黄绿状态。
std::string classify_traffic_light_color(const std::vector<uint8_t>& rgb,
                                         int image_width,
                                         int image_height,
                                         float left,
                                         float top,
                                         float width,
                                         float height) {
    const int x0 = std::clamp(static_cast<int>(left * image_width), 0, std::max(0, image_width - 1));
    const int y0 = std::clamp(static_cast<int>(top * image_height), 0, std::max(0, image_height - 1));
    const int x1 = std::clamp(
        static_cast<int>((left + width) * image_width), x0 + 1, std::max(1, image_width));
    const int y1 = std::clamp(
        static_cast<int>((top + height) * image_height), y0 + 1, std::max(1, image_height));

    int red = 0;
    int yellow = 0;
    int green = 0;
    for (int y = y0; y < y1; y += 2) {
        for (int x = x0; x < x1; x += 2) {
            const size_t offset = (static_cast<size_t>(y) * image_width + x) * 3;
            if (offset + 2 >= rgb.size()) continue;
            const int r = rgb[offset];
            const int g = rgb[offset + 1];
            const int b = rgb[offset + 2];
            if (r > 125 && r > g * 1.25f && r > b * 1.4f) red += 1;
            if (r > 130 && g > 105 && b < 95 && std::abs(r - g) < 90) yellow += 1;
            if (g > 120 && g > r * 1.18f && g > b * 1.25f) green += 1;
        }
    }

    if (green > red && green > yellow) return "traffic_light_green";
    if (yellow > red && yellow >= green) return "traffic_light_yellow";
    return "traffic_light_red";
}

// AI辅助生成：Codex.2026-04-28) 用颜色和边缘线索补充盲道、台阶等场景目标。
void append_scene_cue_detections(std::vector<NativeDetection>& detections,
                                 const std::vector<uint8_t>& rgb,
                                 int image_width,
                                 int image_height) {
    if (image_width <= 0 || image_height <= 0 || rgb.empty()) return;

    auto has_class = [&](const std::string& class_name) {
        return std::any_of(detections.begin(), detections.end(), [&](const NativeDetection& item) {
            return item.class_name == class_name;
        });
    };

    if (!has_class("tactile_paving")) {
        int yellow_count = 0;
        int sample_count = 0;
        const int x0 = image_width * 28 / 100;
        const int x1 = image_width * 72 / 100;
        const int y0 = image_height * 55 / 100;
        const int y1 = image_height * 94 / 100;
        for (int y = y0; y < y1; y += 3) {
            for (int x = x0; x < x1; x += 3) {
                const size_t offset = (static_cast<size_t>(y) * image_width + x) * 3;
                if (offset + 2 >= rgb.size()) continue;
                const int r = rgb[offset];
                const int g = rgb[offset + 1];
                const int b = rgb[offset + 2];
                if (r > 105 && g > 90 && b < 95 && r + g > b * 3) yellow_count += 1;
                sample_count += 1;
            }
        }
        const float yellow_ratio =
            sample_count == 0 ? 0.0f : static_cast<float>(yellow_count) / sample_count;
        if (yellow_ratio > 0.08f) {
            detections.push_back({
                "tactile_paving",
                std::clamp(0.48f + yellow_ratio * 2.0f, 0.55f, 0.82f),
                0.30f,
                0.56f,
                0.40f,
                0.38f,
                1.3f,
                "center",
                0.38f,
            });
        }
    }

    if (!has_class("stairs")) {
        int strong_rows = 0;
        const int x0 = image_width * 14 / 100;
        const int x1 = image_width * 86 / 100;
        const int y0 = image_height * 42 / 100;
        const int y1 = image_height * 90 / 100;
        for (int y = y0 + 4; y < y1; y += 4) {
            int row_edges = 0;
            for (int x = x0; x < x1; x += 4) {
                const size_t a = (static_cast<size_t>(y) * image_width + x) * 3;
                const size_t b = (static_cast<size_t>(y - 4) * image_width + x) * 3;
                if (a + 2 >= rgb.size() || b + 2 >= rgb.size()) continue;
                const int la = static_cast<int>(0.299f * rgb[a] + 0.587f * rgb[a + 1] + 0.114f * rgb[a + 2]);
                const int lb = static_cast<int>(0.299f * rgb[b] + 0.587f * rgb[b + 1] + 0.114f * rgb[b + 2]);
                if (std::abs(la - lb) > 42) row_edges += 1;
            }
            if (row_edges > (x1 - x0) / 28) strong_rows += 1;
        }
        if (strong_rows >= 6) {
            detections.push_back({
                "stairs",
                std::clamp(0.52f + strong_rows / 60.0f, 0.58f, 0.78f),
                0.18f,
                0.46f,
                0.64f,
                0.38f,
                1.5f,
                "center",
                0.82f,
            });
        }
    }
}

// AI辅助生成：Codex.2026-04-24) 按风险和置信度排序，并过滤重复检测框。
void keep_top_detections(std::vector<NativeDetection>& detections, size_t limit) {
    std::sort(detections.begin(), detections.end(), [](const NativeDetection& a, const NativeDetection& b) {
        if (a.risk != b.risk) return a.risk > b.risk;
        return a.score > b.score;
    });

    std::vector<NativeDetection> kept;
    for (const NativeDetection& detection : detections) {
        bool duplicate = false;
        for (const NativeDetection& item : kept) {
            if (detection.class_name == item.class_name && detection_iou(detection, item) > 0.45f) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        kept.push_back(detection);
        if (kept.size() >= limit) break;
    }
    detections = kept;
}

// AI辅助生成：Codex.2026-04-26) 将 C++ 检测结果组装成 Kotlin 可接收的对象数组。
jobjectArray make_detection_array(JNIEnv* env,
                                  jclass cls,
                                  const std::vector<NativeDetection>& detections) {
    jobjectArray result =
        env->NewObjectArray(static_cast<jsize>(detections.size()), cls, nullptr);
    for (jsize i = 0; i < static_cast<jsize>(detections.size()); ++i) {
        const NativeDetection& detection = detections[static_cast<size_t>(i)];
        jobject item = make_detection(
            env,
            detection.class_name.c_str(),
            detection.score,
            detection.left,
            detection.top,
            detection.width,
            detection.height,
            detection.distance,
            detection.direction,
            detection.risk);
        if (item == nullptr) return result;
        env->SetObjectArrayElement(result, i, item);
        env->DeleteLocalRef(item);
    }
    return result;
}

#if VISION_GUARD_WITH_NCNN
    float output_value(const ncnn::Mat& output, int row, int candidate) {
    if (output.dims == 2) {
        if (output.h <= output.w) {
            return output.row(row)[candidate];
        }
        return output.row(candidate)[row];
    }

    if (output.dims == 3) {
        if (output.c <= output.w * output.h) {
            return output.channel(row)[candidate];
        }
        return output.channel(candidate).row(0)[row];
    }

    return 0.0f;
}

std::string app_class_for_yolo26(int class_index) {
    switch (class_index) {
        case 0:
            return "person";
        case 1:  // rider
        case 2:  // car
        case 3:  // bus
        case 4:  // truck
        case 5:  // bike
        case 6:  // motor
        case 9:  // train
            return "vehicle";
        case 7:
            return "traffic_light_red";
        case 8:  // traffic sign
        default:
            return "obstacle";
    }
}

float iou_of(const NativeDetection& a, const NativeDetection& b) {
    const float a_right = a.left + a.width;
    const float a_bottom = a.top + a.height;
    const float b_right = b.left + b.width;
    const float b_bottom = b.top + b.height;
    const float inter_left = std::max(a.left, b.left);
    const float inter_top = std::max(a.top, b.top);
    const float inter_right = std::min(a_right, b_right);
    const float inter_bottom = std::min(a_bottom, b_bottom);
    const float inter_width = std::max(0.0f, inter_right - inter_left);
    const float inter_height = std::max(0.0f, inter_bottom - inter_top);
    const float inter_area = inter_width * inter_height;
    const float union_area = a.width * a.height + b.width * b.height - inter_area;
    return union_area <= 0.0f ? 0.0f : inter_area / union_area;
}

// AI辅助生成：Codex.2026-04-28) 解码 YOLOv8 风格 out0 输出并转换为 App 目标结构。
std::vector<NativeDetection> decode_yolov8_output(const ncnn::Mat& output,
                                                  const LetterboxInfo& letterbox,
                                                  const std::vector<uint8_t>& rgb) {
    int candidate_count = 0;
    int row_count = 0;
    if (output.dims == 2) {
        row_count = std::min(output.w, output.h);
        candidate_count = std::max(output.w, output.h);
    } else if (output.dims == 3) {
        row_count = output.c >= 84 ? output.c : output.h;
        candidate_count = output.c >= 84 ? output.w * output.h : output.w;
    }
    if (row_count < 5 || candidate_count <= 0) return {};

    const int class_count = row_count - 4;
    std::vector<NativeDetection> proposals;
    proposals.reserve(64);
    for (int i = 0; i < candidate_count; ++i) {
        float best_score = -std::numeric_limits<float>::infinity();
        int best_class = -1;
        for (int c = 0; c < class_count; ++c) {
            const float score = output_value(output, 4 + c, i);
            if (score > best_score) {
                best_score = score;
                best_class = c;
            }
        }
        if (best_score < g_threshold || best_class < 0) continue;

        const float cx = output_value(output, 0, i);
        const float cy = output_value(output, 1, i);
        const float box_w = output_value(output, 2, i);
        const float box_h = output_value(output, 3, i);
        float left = (cx - box_w * 0.5f - letterbox.pad_x) / letterbox.scale;
        float top = (cy - box_h * 0.5f - letterbox.pad_y) / letterbox.scale;
        float right = (cx + box_w * 0.5f - letterbox.pad_x) / letterbox.scale;
        float bottom = (cy + box_h * 0.5f - letterbox.pad_y) / letterbox.scale;
        left = std::clamp(left / std::max(1, letterbox.rotated_width), 0.0f, 1.0f);
        top = std::clamp(top / std::max(1, letterbox.rotated_height), 0.0f, 1.0f);
        right = std::clamp(right / std::max(1, letterbox.rotated_width), 0.0f, 1.0f);
        bottom = std::clamp(bottom / std::max(1, letterbox.rotated_height), 0.0f, 1.0f);
        const float normalized_width = right - left;
        const float normalized_height = bottom - top;
        if (normalized_width <= 0.01f || normalized_height <= 0.01f) continue;

        const float center_x = (left + right) * 0.5f;
        const char* direction = direction_for_center(center_x);
        std::string class_name = app_class_for_yolo26(best_class);
        if (best_class == 7) {
            class_name = classify_traffic_light_color(
                rgb,
                letterbox.rotated_width,
                letterbox.rotated_height,
                left,
                top,
                normalized_width,
                normalized_height);
        }
        const float distance = std::clamp(1.8f / std::max(0.18f, normalized_height), 0.6f, 5.0f);
        float risk = best_score * 0.55f + normalized_height * 0.9f;
        if (class_name == "traffic_light_red") risk += 0.35f;
        if (class_name == "traffic_light_yellow") risk += 0.18f;
        if (class_name == "traffic_light_green") risk -= 0.22f;
        if (class_name == "vehicle") risk += 0.15f;
        if (direction == std::string("center")) risk += 0.12f;
        risk = std::clamp(risk, 0.0f, 1.0f);

        proposals.push_back({
            class_name,
            best_score,
            left,
            top,
            normalized_width,
            normalized_height,
            distance,
            direction,
            risk,
        });
    }

    keep_top_detections(proposals, 3);
    return proposals;
}
#endif
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_vision_1guard_NcnnVisionEngine_nativeInit(
    JNIEnv* env,
    jobject /* thiz */,
    jstring param_path,
    jstring bin_path,
    jstring classes_path,
    jstring preprocess_path,
    jint input_size,
    jfloat threshold) {
    // AI辅助生成：Codex.2026-04-27) 初始化 NCNN 网络并加载模型、类别和预处理配置。
    g_input_size = input_size;
    g_threshold = threshold;
    const char* param = param_path ? env->GetStringUTFChars(param_path, nullptr) : "";
    const char* bin = bin_path ? env->GetStringUTFChars(bin_path, nullptr) : "";
    const char* classes = classes_path ? env->GetStringUTFChars(classes_path, nullptr) : "";
    const char* preprocess = preprocess_path ? env->GetStringUTFChars(preprocess_path, nullptr) : "";
    if (classes && classes[0] != '\0') load_classes(classes);
    const std::string preprocess_json = preprocess && preprocess[0] != '\0' ? read_file(preprocess) : "";

    LOGI("init input=%d threshold=%.2f param=%s bin=%s classes=%zu preprocess_bytes=%zu",
         g_input_size,
         g_threshold,
         param,
         bin,
         g_classes.size(),
         preprocess_json.size());

#if VISION_GUARD_WITH_NCNN
    if (param && param[0] != '\0' && bin && bin[0] != '\0') {
        g_net.clear();
        g_net.opt.use_vulkan_compute = false;
        g_net.opt.num_threads = 4;
        const int param_result = g_net.load_param(param);
        const int model_result = g_net.load_model(bin);
        g_ncnn_ready = param_result == 0 && model_result == 0;
        if (!g_ncnn_ready) {
            LOGW("NCNN load failed param_result=%d model_result=%d", param_result, model_result);
        }
    }
#else
    g_ncnn_ready = false;
    LOGW("NCNN is not linked. Using native heuristic fallback until libncnn.so and headers are added.");
#endif

    if (param_path) env->ReleaseStringUTFChars(param_path, param);
    if (bin_path) env->ReleaseStringUTFChars(bin_path, bin);
    if (classes_path) env->ReleaseStringUTFChars(classes_path, classes);
    if (preprocess_path) env->ReleaseStringUTFChars(preprocess_path, preprocess);
    return JNI_TRUE;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_example_vision_1guard_NcnnVisionEngine_nativeDetectYuv420(
    JNIEnv* env,
    jobject /* thiz */,
    jbyteArray y,
    jbyteArray u,
    jbyteArray v,
    jint width,
    jint height,
    jint rotation,
    jintArray bytes_per_row,
    jintArray bytes_per_pixel) {
    // AI辅助生成：Codex.2026-04-28) 原生检测入口，负责预处理、NCNN 推理、补充线索和 fallback。
    jclass cls = env->FindClass("com/example/vision_guard/DetectionNative");
    if (cls == nullptr) return nullptr;

#if VISION_GUARD_WITH_NCNN
    if (g_ncnn_ready && y && u && v && width > 0 && height > 0) {
        std::vector<int> row_strides;
        std::vector<int> pixel_strides;
        if (bytes_per_row) {
            const int count = env->GetArrayLength(bytes_per_row);
            row_strides.resize(count);
            env->GetIntArrayRegion(bytes_per_row, 0, count, row_strides.data());
        }
        if (bytes_per_pixel) {
            const int count = env->GetArrayLength(bytes_per_pixel);
            pixel_strides.resize(count);
            env->GetIntArrayRegion(bytes_per_pixel, 0, count, pixel_strides.data());
        }

        jbyte* y_bytes = env->GetByteArrayElements(y, nullptr);
        jbyte* u_bytes = env->GetByteArrayElements(u, nullptr);
        jbyte* v_bytes = env->GetByteArrayElements(v, nullptr);
        const int y_length = env->GetArrayLength(y);
        const int u_length = env->GetArrayLength(u);
        const int v_length = env->GetArrayLength(v);

        int rotated_width = 0;
        int rotated_height = 0;
        std::vector<uint8_t> rgb = yuv420_to_rotated_rgb(
            reinterpret_cast<const uint8_t*>(y_bytes),
            reinterpret_cast<const uint8_t*>(u_bytes),
            reinterpret_cast<const uint8_t*>(v_bytes),
            y_length,
            u_length,
            v_length,
            width,
            height,
            rotation,
            row_strides.data(),
            static_cast<int>(row_strides.size()),
            pixel_strides.data(),
            static_cast<int>(pixel_strides.size()),
            rotated_width,
            rotated_height);
        apply_adaptive_contrast(rgb);

        env->ReleaseByteArrayElements(y, y_bytes, JNI_ABORT);
        env->ReleaseByteArrayElements(u, u_bytes, JNI_ABORT);
        env->ReleaseByteArrayElements(v, v_bytes, JNI_ABORT);

        LetterboxInfo letterbox{};
        std::vector<uint8_t> input_pixels =
            letterbox_rgb(rgb, rotated_width, rotated_height, g_input_size, letterbox);
        ncnn::Mat input = ncnn::Mat::from_pixels(
            input_pixels.data(), ncnn::Mat::PIXEL_RGB, g_input_size, g_input_size);
        const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
        input.substract_mean_normalize(nullptr, norm_vals);

        ncnn::Extractor extractor = g_net.create_extractor();
        extractor.set_light_mode(true);
        ncnn::Mat output;
        if (extractor.input("in0", input) == 0 && extractor.extract("out0", output) == 0) {
            static bool output_shape_logged = false;
            if (!output_shape_logged) {
                LOGI("output dims=%d w=%d h=%d c=%d", output.dims, output.w, output.h, output.c);
                output_shape_logged = true;
            }
            std::vector<NativeDetection> decoded = decode_yolov8_output(output, letterbox, rgb);
            append_scene_cue_detections(decoded, rgb, rotated_width, rotated_height);
            keep_top_detections(decoded, 3);
            return make_detection_array(env, cls, decoded);
        }
        LOGW("NCNN extract failed. Falling back to luminance heuristic.");
    }
#endif

    if (!y || width <= 0 || height <= 0) {
        return env->NewObjectArray(0, cls, nullptr);
    }

    int row_stride = width;
    if (bytes_per_row && env->GetArrayLength(bytes_per_row) > 0) {
        jint* strides = env->GetIntArrayElements(bytes_per_row, nullptr);
        row_stride = strides[0] > 0 ? strides[0] : width;
        env->ReleaseIntArrayElements(bytes_per_row, strides, JNI_ABORT);
    }

    jbyte* y_bytes = env->GetByteArrayElements(y, nullptr);
    const auto* y_plane = reinterpret_cast<const uint8_t*>(y_bytes);
    const RegionStats scene = sample_region(
        y_plane, width, height, row_stride, 0.05f, 0.34f, 0.95f, 0.84f, false);
    const std::vector<RegionCandidate> candidates = {
        {"left", 0.06f, 0.38f, 0.34f, 0.84f},
        {"center", 0.32f, 0.36f, 0.68f, 0.84f},
        {"right", 0.66f, 0.38f, 0.94f, 0.84f},
    };
    std::vector<NativeDetection> detections;
    detections.reserve(3);
    for (const RegionCandidate& candidate : candidates) {
        const RegionStats stats = sample_region(
            y_plane,
            width,
            height,
            row_stride,
            candidate.left,
            candidate.top,
            candidate.right,
            candidate.bottom,
            false);
        const float darker_than_scene = scene.mean - stats.mean;
        const bool has_large_dark_object = darker_than_scene > 30.0f && stats.dark_ratio > 0.32f;
        const bool has_strong_texture = stats.variance > 1600.0f && stats.dark_ratio > 0.28f;
        if (!has_large_dark_object && !has_strong_texture) continue;

        const float score = std::clamp(
            0.52f + std::max(0.0f, darker_than_scene) / 130.0f + stats.dark_ratio / 4.0f,
            0.55f,
            0.90f);
        if (score < g_threshold) continue;
        detections.push_back({
            "obstacle",
            score,
            candidate.left,
            candidate.top,
            candidate.right - candidate.left,
            candidate.bottom - candidate.top,
            stats.dark_ratio > 0.42f ? 1.0f : 1.8f,
            candidate.direction,
            has_large_dark_object ? 0.88f : 0.70f,
        });
    }
    env->ReleaseByteArrayElements(y, y_bytes, JNI_ABORT);

    if (detections.empty()) {
        return env->NewObjectArray(0, cls, nullptr);
    }
    keep_top_detections(detections, 3);
    return make_detection_array(env, cls, detections);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_vision_1guard_NcnnVisionEngine_nativeRelease(
    JNIEnv* /* env */,
    jobject /* thiz */) {
#if VISION_GUARD_WITH_NCNN
    g_net.clear();
#endif
    g_ncnn_ready = false;
    LOGI("release");
}
