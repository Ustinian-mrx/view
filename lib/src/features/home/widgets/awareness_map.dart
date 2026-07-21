import 'package:flutter/material.dart';

import '../../../core/detection.dart';

// AI辅助生成：Codex.2026-04-28) 用简化雷达图表达前方目标方位和距离感。
class AwarenessMap extends StatelessWidget {
  const AwarenessMap({super.key, required this.frame});

  final DetectionFrame? frame;

  @override
  Widget build(BuildContext context) {
    final detections = frame?.detections ?? const <Detection>[];
    final targetCount = detections.length;

    final description = detections.isEmpty
        ? '环境感知地图，未检测到目标'
        : '环境感知地图，检测到$targetCount个目标：${detections.take(3).map((d) => '${d.direction.label}${d.type.label}').join('、')}';

    return Semantics(
      label: description,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          height: 104,
          child: CustomPaint(
            painter: _AwarenessMapPainter(frame),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.near_me_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '环境感知',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$targetCount 个目标',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AwarenessMapPainter extends CustomPainter {
  _AwarenessMapPainter(this.frame);

  final DetectionFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.18);
    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.tealAccent.withValues(alpha: 0.7);

    final origin = Offset(size.width / 2, size.height - 12);
    for (final radius in const [28.0, 54.0, 80.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        3.85,
        1.58,
        false,
        gridPaint,
      );
    }
    canvas.drawLine(origin, Offset(size.width * 0.22, 28), gridPaint);
    canvas.drawLine(origin, Offset(size.width * 0.50, 24), pathPaint);
    canvas.drawLine(origin, Offset(size.width * 0.78, 28), gridPaint);

    final detections = frame?.detections.take(3) ?? const Iterable<Detection>.empty();
    for (final detection in detections) {
      final centerX = (detection.box.center.dx * size.width).clamp(18.0, size.width - 18);
      final distanceRatio = (detection.distanceMeters == null
              ? 0.55
              : (detection.distanceMeters! / 3.0).clamp(0.18, 0.92))
          .toDouble();
      final centerY = size.height - 18 - distanceRatio * 70;
      final color = _colorFor(detection);
      canvas.drawCircle(
        Offset(centerX, centerY),
        8 + detection.riskScore * 5,
        Paint()..color = color.withValues(alpha: 0.28),
      );
      canvas.drawCircle(
        Offset(centerX, centerY),
        5,
        Paint()..color = color,
      );
    }
  }

  Color _colorFor(Detection detection) {
    return switch (detection.type) {
      DetectionClass.obstacle ||
      DetectionClass.stairs ||
      DetectionClass.trafficLightRed =>
        Colors.redAccent,
      DetectionClass.trafficLightYellow => Colors.amberAccent,
      DetectionClass.tactilePaving ||
      DetectionClass.trafficLightGreen =>
        Colors.lightGreenAccent,
      _ => Colors.cyanAccent,
    };
  }

  @override
  bool shouldRepaint(covariant _AwarenessMapPainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
