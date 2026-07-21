import 'package:flutter/material.dart';

import '../../../core/app_settings.dart';
import '../../../core/detection.dart';

// AI辅助生成：Codex.2026-04-28) 展示延迟、目标数、阈值和最近检测目标。
class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, required this.frame, required this.settings});

  final DetectionFrame? frame;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final detections = frame?.detections ?? const <Detection>[];
    return Semantics(
      label: '检测状态面板，延迟${frame?.latencyMs ?? 0}毫秒，检测到${detections.length}个目标',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Metric(label: '延迟', value: '${frame?.latencyMs ?? 0} ms'),
                const SizedBox(width: 10),
                _Metric(label: '目标', value: '${detections.length}/3'),
                const SizedBox(width: 10),
                _Metric(
                  label: '阈值',
                  value: settings.confidenceThreshold.toStringAsFixed(2),
                ),
                const SizedBox(width: 10),
                _Metric(
                  label: '输入',
                  value: frame == null || frame!.inputWidth == 0
                      ? '${settings.inputSize}'
                      : '${frame!.inputWidth}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (detections.isEmpty)
              Semantics(
                liveRegion: true,
                child: Text(
                  '持续扫描中，保持手机朝向前方',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Semantics(
                liveRegion: true,
                label: detections.take(3).map((item) =>
                    '${item.direction.label}${item.type.label} ${(item.score * 100).round()}%').join('，'),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detections.take(3).map((item) {
                    return Chip(
                      avatar: Icon(_iconFor(item.type), size: 18),
                      label: Text(
                        '${item.direction.label}${item.type.label} '
                        '${(item.score * 100).round()}%',
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(DetectionClass type) {
    return switch (type) {
      DetectionClass.person => Icons.directions_walk_rounded,
      DetectionClass.vehicle => Icons.directions_car_rounded,
      DetectionClass.tactilePaving => Icons.route_rounded,
      DetectionClass.trafficLightRed ||
      DetectionClass.trafficLightGreen ||
      DetectionClass.trafficLightYellow =>
        Icons.traffic_rounded,
      DetectionClass.stairs => Icons.stairs_rounded,
      _ => Icons.center_focus_strong_rounded,
    };
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: '$label $value',
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
