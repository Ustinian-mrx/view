import 'dart:ui';

enum DetectionClass {
  obstacle,
  tactilePaving,
  stairs,
  trafficLightRed,
  trafficLightGreen,
  trafficLightYellow,
  person,
  vehicle,
  unknown;

  static DetectionClass fromName(String name) {
    return switch (name) {
      'obstacle' => DetectionClass.obstacle,
      'tactile_paving' => DetectionClass.tactilePaving,
      'stairs' => DetectionClass.stairs,
      'traffic_light_red' => DetectionClass.trafficLightRed,
      'traffic_light_green' => DetectionClass.trafficLightGreen,
      'traffic_light_yellow' => DetectionClass.trafficLightYellow,
      'person' => DetectionClass.person,
      'vehicle' => DetectionClass.vehicle,
      _ => DetectionClass.unknown,
    };
  }

  String get label {
    return switch (this) {
      DetectionClass.obstacle => '\u969c\u788d\u7269',
      DetectionClass.tactilePaving => '\u76f2\u9053',
      DetectionClass.stairs => '\u53f0\u9636',
      DetectionClass.trafficLightRed => '\u7ea2\u706f',
      DetectionClass.trafficLightGreen => '\u7eff\u706f',
      DetectionClass.trafficLightYellow => '\u9ec4\u706f',
      DetectionClass.person => '\u884c\u4eba',
      DetectionClass.vehicle => '\u8f66\u8f86',
      DetectionClass.unknown => '\u672a\u77e5\u76ee\u6807',
    };
  }
}

enum RiskLevel { safe, notice, warning, danger }

enum ObjectDirection {
  left,
  center,
  right,
  unknown;

  static ObjectDirection fromName(String? name) {
    return switch (name) {
      'left' => ObjectDirection.left,
      'center' => ObjectDirection.center,
      'right' => ObjectDirection.right,
      _ => ObjectDirection.unknown,
    };
  }

  String get label {
    return switch (this) {
      ObjectDirection.left => '\u5de6\u4fa7',
      ObjectDirection.center => '\u6b63\u524d\u65b9',
      ObjectDirection.right => '\u53f3\u4fa7',
      ObjectDirection.unknown => '\u524d\u65b9',
    };
  }
}

class Detection {
  const Detection({
    required this.type,
    required this.score,
    required this.box,
    required this.distanceMeters,
    required this.direction,
    required this.riskScore,
  });

  // AI辅助生成：Codex.2026-03-25) 将原生检测 Map 转换为 Flutter 侧目标对象。
  factory Detection.fromMap(Map<dynamic, dynamic> map) {
    final box = (map['box'] as List<dynamic>? ?? const [0, 0, 0, 0])
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
    final safeBox = box.length >= 4 ? box : const [0.0, 0.0, 0.0, 0.0];
    final rawDistance = (map['distanceMeters'] as num?)?.toDouble();
    return Detection(
      type: DetectionClass.fromName(map['class'] as String? ?? 'unknown'),
      score: (map['score'] as num? ?? 0).toDouble(),
      box: Rect.fromLTWH(safeBox[0], safeBox[1], safeBox[2], safeBox[3]),
      distanceMeters:
          rawDistance == null || rawDistance < 0 ? null : rawDistance,
      direction: ObjectDirection.fromName(map['direction'] as String?),
      riskScore: (map['riskScore'] as num? ?? 0).toDouble(),
    );
  }

  final DetectionClass type;
  final double score;
  final Rect box;
  final double? distanceMeters;
  final ObjectDirection direction;
  final double riskScore;
}

class DetectionFrame {
  const DetectionFrame({
    required this.timestamp,
    required this.latencyMs,
    required this.inputWidth,
    required this.inputHeight,
    required this.detections,
  });

  // AI辅助生成：Codex.2026-04-28) 解析原生层返回的检测帧数据，统一给 UI 和提醒模块使用。
  factory DetectionFrame.fromMap(Map<dynamic, dynamic> map) {
    final raw = map['detections'] as List<dynamic>? ?? const [];
    return DetectionFrame(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      latencyMs: (map['latencyMs'] as num? ?? 0).toInt(),
      inputWidth: (map['inputWidth'] as num? ?? 0).toInt(),
      inputHeight: (map['inputHeight'] as num? ?? 0).toInt(),
      detections: raw
          .map((item) => Detection.fromMap(item as Map<dynamic, dynamic>))
          .toList(growable: false),
    );
  }

  final DateTime timestamp;
  final int latencyMs;
  final int inputWidth;
  final int inputHeight;
  final List<Detection> detections;

  // AI辅助生成：Codex.2026-04-28) 将多目标检测结果归纳为页面和播报使用的风险等级。
  RiskLevel get risk {
    if (detections.any((d) =>
        d.type == DetectionClass.obstacle ||
        d.type == DetectionClass.stairs ||
        d.type == DetectionClass.trafficLightRed)) {
      return RiskLevel.danger;
    }
    if (detections.any((d) => d.type == DetectionClass.trafficLightYellow)) {
      return RiskLevel.warning;
    }
    if (detections.isNotEmpty) return RiskLevel.notice;
    return RiskLevel.safe;
  }

  // AI辅助生成：Codex.2026-04-28) 从多目标中挑出最需要优先播报的目标。
  Detection? get primary {
    if (detections.isEmpty) return null;
    final sorted = [...detections]..sort((a, b) {
        final typeWeight = _priority(b.type).compareTo(_priority(a.type));
        if (typeWeight != 0) return typeWeight;
        final riskWeight = b.riskScore.compareTo(a.riskScore);
        if (riskWeight != 0) return riskWeight;
        return b.score.compareTo(a.score);
      });
    return sorted.first;
  }

  static int _priority(DetectionClass type) {
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
}
