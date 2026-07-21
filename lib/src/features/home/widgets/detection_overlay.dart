import 'package:flutter/material.dart';

import '../../../core/detection.dart';

// AI辅助生成：Codex.2026-04-28) 在相机预览上绘制检测框和置信度标签。
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({super.key, required this.frame});

  final DetectionFrame? frame;

  @override
  Widget build(BuildContext context) {
    final detections = frame?.detections ?? const <Detection>[];
    return Semantics(
      label: detections.isEmpty
          ? '未检测到目标'
          : '检测到${detections.length}个目标：${detections.take(3).map((d) => '${d.type.label}${d.direction.label}').join('、')}',
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DetectionPainter(frame),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter(this.frame);

  final DetectionFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final detections = frame?.detections ?? const <Detection>[];
    for (final detection in detections) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _colorFor(detection.type);
      final rect = Rect.fromLTWH(
        detection.box.left * size.width,
        detection.box.top * size.height,
        detection.box.width * size.width,
        detection.box.height * size.height,
      );
      canvas.drawRect(rect, paint);
      _drawLabel(canvas, rect, detection, paint.color);
    }
  }

  void _drawLabel(Canvas canvas, Rect rect, Detection detection, Color color) {
    final text = '${detection.type.label} ${(detection.score * 100).round()}%';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelRect = Rect.fromLTWH(
      rect.left,
      (rect.top - painter.height - 6).clamp(0, double.infinity),
      painter.width + 12,
      painter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      Paint()..color = color.withValues(alpha: 0.85),
    );
    painter.paint(canvas, labelRect.topLeft + const Offset(6, 3));
  }

  Color _colorFor(DetectionClass type) {
    return switch (type) {
      DetectionClass.obstacle ||
      DetectionClass.stairs ||
      DetectionClass.trafficLightRed =>
        Colors.redAccent,
      DetectionClass.trafficLightYellow => Colors.amberAccent,
      DetectionClass.trafficLightGreen ||
      DetectionClass.tactilePaving =>
        Colors.lightGreenAccent,
      _ => Colors.cyanAccent,
    };
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
