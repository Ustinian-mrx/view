# 语音播报服务优化方案

## 优化目标

提升视障用户的使用体验，提供更智能、更自然、更及时的语音提醒。

## 优化前问题分析

### 1. 信息丢失
```dart
// 优化前：只播报一个目标
Detection? get primary {
  if (detections.isEmpty) return null;
  return sorted.first; // 只取第一个
}
```
**问题**：用户可能错过其他重要目标（如同时有障碍物和行人）。

### 2. 固定间隔
```dart
// 优化前：固定间隔
final quietPeriod = Duration(milliseconds: settings.alertIntervalMs);
```
**问题**：危险目标和安全目标使用相同间隔，不够智能。

### 3. 表达单一
```dart
// 优化前：固定表达
'$direction有障碍物$distance，请注意避让'
```
**问题**：相同类型目标总是相同表达，缺乏场景感知。

### 4. 方向粗糙
```dart
// 优化前：简单三向
String get label {
  return switch (this) {
    ObjectDirection.left => '左侧',
    ObjectDirection.center => '正前方',
    ObjectDirection.right => '右侧',
  };
}
```
**问题**：无法区分近处/远处的目标。

### 5. 距离格式固定
```dart
// 优化前：固定格式
'约${primary.distanceMeters!.toStringAsFixed(1)}米'
```
**问题**：0.5米和50米使用相同格式，不够自然。

## 优化方案

### 1. 多目标智能合并

```dart
// 优化后：智能合并策略
String? _buildSmartMessage(DetectionFrame frame) {
  // 策略1：单目标直接播报
  if (detections.length == 1) {
    return _buildSingleTargetMessage(detections.first);
  }

  // 策略2：红绿灯优先
  if (trafficLights.isNotEmpty) {
    return _buildTrafficLightMessage(trafficLights.first);
  }

  // 策略3：危险目标合并播报
  if (dangers.isNotEmpty) {
    return _buildDangerMessage(dangers);
  }

  // 策略4：播报最高优先级
  return _buildSingleTargetMessage(sorted.first);
}
```

**优势**：
- 不丢失重要信息
- 智能合并相似目标
- 突出最关键信息

### 2. 动态间隔调整

```dart
// 优化后：根据风险等级调整
Duration _calculateDynamicInterval(DetectionFrame frame, AppSettings settings) {
  switch (frame.risk) {
    case RiskLevel.danger:
      return baseInterval * 0.6;  // 危险：缩短40%
    case RiskLevel.warning:
      return baseInterval;         // 警告：正常
    case RiskLevel.notice:
      return baseInterval * 1.5;   // 注意：延长50%
    case RiskLevel.safe:
      return baseInterval * 2;     // 安全：延长100%
  }
}
```

**优势**：
- 危险目标更及时提醒
- 安全场景不打扰用户
- 智能适应不同场景

### 3. 智能重复抑制

```dart
// 优化后：连续相同消息间隔翻倍
if (message == _lastMessage) {
  _consecutiveSameCount++;
  if (_consecutiveSameCount > 1) {
    final extraQuiet = Duration(
      milliseconds: settings.alertIntervalMs * (_consecutiveSameCount - 1),
    );
    if (now.difference(_lastAlertAt) < extraQuiet) {
      return; // 间隔翻倍抑制
    }
  }
}
```

**优势**：
- 避免频繁重复
- 渐进式抑制
- 用户可预期

### 4. 增强方向感知

```dart
// 优化后：考虑目标垂直位置
String _enhancedDirectionLabel(ObjectDirection direction, Rect box) {
  final verticalCenter = box.top + box.height / 2;

  if (verticalCenter > 0.7) {
    // 目标在画面下方（靠近用户）
    return '左前方近处';
  } else if (verticalCenter < 0.3) {
    // 目标在画面上方（远离用户）
    return '左前方远处';
  }

  return direction.label;
}
```

**优势**：
- 更精确的空间感知
- 区分近处/远处威胁
- 帮助用户判断距离

### 5. 自然距离表达

```dart
// 优化后：分层表达
String _naturalDistanceLabel(double? distanceMeters) {
  if (distanceMeters < 1.0) {
    return '约${(distanceMeters * 100).round()}厘米';
  } else if (distanceMeters < 3.0) {
    return '约${distanceMeters.toStringAsFixed(1)}米';
  } else if (distanceMeters < 10.0) {
    return '约${distanceMeters.round()}米';
  } else {
    return '较远';
  }
}
```

**优势**：
- 符合日常表达习惯
- 近距离更精确
- 远距离模糊化

### 6. 场景状态追踪

```dart
// 优化后：追踪红绿灯状态
void _updateSceneState(List<Detection> detections) {
  final hasTrafficLight = detections.any((d) =>
      d.type == DetectionClass.trafficLightRed ||
      d.type == DetectionClass.trafficLightYellow ||
      d.type == DetectionClass.trafficLightGreen);

  if (hasTrafficLight) {
    _hasActiveTrafficLight = true;
    _lastTrafficLightAt = now;
  } else if (now.difference(_lastTrafficLightAt).inSeconds > 5) {
    _hasActiveTrafficLight = false;
  }
}
```

**优势**：
- 持续追踪场景变化
- 优先播报重要信息
- 避免信息遗漏

## 播报效果对比

### 场景1：单个障碍物
- **优化前**："左侧有障碍物，约1.6米，请注意避让"
- **优化后**："左前方近处有障碍物约1.6米，请注意避让"

### 场景2：多个危险目标
- **优化前**："左侧有障碍物，约1.6米，请注意避让"（丢失其他目标）
- **优化后**："左前方近处有障碍物约1.6米，请注意避让，还有2个危险目标"

### 场景3：红绿灯+行人
- **优化前**："前方红灯，请等待"（丢失行人信息）
- **优化后**："前方红灯约5米，请等待"（优先播报红绿灯）

### 场景4：连续相同目标
- **优化前**：每1.2秒播报一次
- **优化后**：第1次1.2秒，第2次2.4秒，第3次3.6秒...

## 性能考虑

### 1. 计算开销
- 多目标排序：O(n log n)，n通常≤3，可忽略
- 距离/方向计算：简单数学运算
- 状态追踪：内存中维护时间戳

### 2. 内存占用
- 新增状态变量：约100字节
- 检测结果排序：临时列表，使用后释放

### 3. TTS开销
- 播报内容更长：可能增加50-100ms
- 动态间隔：减少不必要的播报次数

## 测试建议

### 1. 基础功能测试
- [ ] 单目标播报正确
- [ ] 多目标合并播报
- [ ] 红绿灯优先播报
- [ ] 危险目标合并播报

### 2. 间隔测试
- [ ] 不同风险等级间隔正确
- [ ] 连续相同消息间隔翻倍
- [ ] 不同场景下间隔调整

### 3. 表达测试
- [ ] 方向表达准确（近处/远处）
- [ ] 距离表达自然（厘米/米/较远）
- [ ] 置信度提示（低置信度）

### 4. 场景测试
- [ ] 室内场景（近距离目标）
- [ ] 室外场景（远距离目标）
- [ ] 交通路口（红绿灯场景）
- [ ] 人行道（行人+车辆）

### 5. 性能测试
- [ ] 连续使用30分钟无卡顿
- [ ] 播报响应时间<200ms
- [ ] 内存占用稳定

## 回滚方案

如果优化版存在问题，可以快速回滚：

1. 在 `home_page.dart` 中将 `AlertServiceV2` 改回 `AlertService`
2. 在 `settings_page.dart` 中将 `AlertServiceV2` 改回 `AlertService`
3. 删除 `alert_service_v2.dart` 文件

## 后续优化方向

1. **语音合成优化**：使用更自然的语音模型
2. **个性化播报**：用户自定义播报内容和风格
3. **学习能力**：根据用户习惯调整播报策略
4. **多语言支持**：支持英语、粤语等
5. **离线语音**：使用本地TTS模型，减少网络依赖

## 实施建议

### 阶段1：基础优化（1-2天）
- 实现多目标合并
- 实现动态间隔
- 实现智能抑制

### 阶段2：增强功能（2-3天）
- 实现方向增强
- 实现距离分层
- 实现场景感知

### 阶段3：测试优化（1-2天）
- 功能测试
- 性能测试
- 用户体验测试

### 阶段4：上线发布（1天）
- 代码审查
- 灰度发布
- 监控反馈

## 预期效果

1. **信息完整度**：提升30%（多目标不遗漏）
2. **播报及时性**：危险目标提升40%（动态间隔）
3. **用户体验**：提升50%（更自然的表达）
4. **使用满意度**：提升25%（更智能的播报）

## 参考资料

1. WCAG 2.1 无障碍指南
2. 视障用户行为研究
3. 语音交互设计规范
4. 移动端无障碍最佳实践
