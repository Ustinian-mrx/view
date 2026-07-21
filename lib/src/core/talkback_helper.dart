// TalkBack 无障碍辅助工具类
// Flutter 的 Semantics 节点会自动与 TalkBack 对接，无需手动发送事件。
class TalkBackHelper {
  // 获取检测结果的 TalkBack 描述
  static String getDetectionDescription({
    required String type,
    required String direction,
    double? distanceMeters,
    required double confidence,
  }) {
    final distance = _formatDistance(distanceMeters);
    final confidencePercent = (confidence * 100).round();
    return '$direction$type$distance，置信度$confidencePercent%';
  }

  // 获取风险等级的 TalkBack 描述
  static String getRiskDescription(String riskLevel, {int targetCount = 0}) {
    final countDesc = targetCount > 0 ? '，共$targetCount个目标' : '';
    switch (riskLevel) {
      case 'danger':
        return '危险：检测到高风险目标$countDesc，请立即注意避让';
      case 'warning':
        return '警告：检测到需要注意的目标$countDesc，请注意周围环境';
      case 'notice':
        return '注意：检测到低风险目标$countDesc';
      case 'safe':
        return '安全：未发现高风险目标';
      default:
        return '检测中$countDesc';
    }
  }

  static String _formatDistance(double? meters) {
    if (meters == null || meters < 0) return '';
    if (meters < 1.0) return '约${(meters * 100).round()}厘米';
    if (meters < 3.0) return '约${meters.toStringAsFixed(1)}米';
    if (meters < 10.0) return '约${meters.round()}米';
    return '较远';
  }
}
