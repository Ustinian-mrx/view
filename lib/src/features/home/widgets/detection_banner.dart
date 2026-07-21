import 'package:flutter/material.dart';

import '../../../core/detection.dart';

// AI辅助生成：Codex.2026-04-28) 将当前风险等级转换成顶部醒目提示条。
class DetectionBanner extends StatelessWidget {
  const DetectionBanner({super.key, required this.frame});

  final DetectionFrame? frame;

  @override
  Widget build(BuildContext context) {
    final risk = frame?.risk ?? RiskLevel.safe;
    final primary = frame?.primary;
    final count = frame?.detections.length ?? 0;
    final (color, icon, text) = switch (risk) {
      RiskLevel.danger => (
          Colors.redAccent,
          Icons.warning_rounded,
          primary == null ? '注意前方' : '${primary.type.label}，请注意'
        ),
      RiskLevel.warning => (
          Colors.amberAccent,
          Icons.priority_high_rounded,
          primary == null ? '请注意' : '${primary.type.label}，请慢行'
        ),
      RiskLevel.notice => (
          Colors.lightGreenAccent,
          Icons.info_rounded,
          primary == null ? '检测中' : '检测到${primary.type.label}'
        ),
      RiskLevel.safe => (
          Colors.tealAccent,
          Icons.check_circle_rounded,
          '前方暂未发现高风险目标'
        ),
    };

    final displayText = count > 1 ? '$text · 共$count个目标' : text;

    return Semantics(
      liveRegion: true,
      label: '风险提示：$displayText',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.76),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
