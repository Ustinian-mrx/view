// AI辅助生成：Codex.2026-03-22) 管理运行时提醒和推理参数的轻量配置对象。
class AppSettings {
  const AppSettings({
    required this.voiceEnabled,
    required this.vibrationEnabled,
    required this.confidenceThreshold,
    required this.alertIntervalMs,
    required this.inputSize,
  });

  static const defaults = AppSettings(
    voiceEnabled: true,
    vibrationEnabled: true,
    confidenceThreshold: 0.25,
    alertIntervalMs: 1200,
    inputSize: 640,
  );

  final bool voiceEnabled;
  final bool vibrationEnabled;
  final double confidenceThreshold;
  final int alertIntervalMs;
  final int inputSize;

  static AppSettings _cached = defaults;

  AppSettings copyWith({
    bool? voiceEnabled,
    bool? vibrationEnabled,
    double? confidenceThreshold,
    int? alertIntervalMs,
    int? inputSize,
  }) {
    return AppSettings(
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      alertIntervalMs: alertIntervalMs ?? this.alertIntervalMs,
      inputSize: inputSize ?? this.inputSize,
    );
  }

  static Future<AppSettings> load() async {
    return _cached;
  }

  Future<void> save() async {
    _cached = this;
  }
}
