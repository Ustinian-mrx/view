import 'package:flutter/material.dart';

import '../../core/alert_service.dart';
import '../../core/app_settings.dart';

// AI辅助生成：Codex.2026-04-28) 提供提醒方式、阈值和模型输入相关运行设置。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _alerts = AlertService();
  AppSettings _settings = AppSettings.defaults;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await AppSettings.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loaded = true;
    });
  }

  // AI辅助生成：Codex.2026-04-28) 保存设置并立即同步到提醒服务。
  Future<void> _save(AppSettings settings) async {
    setState(() => _settings = settings);
    await settings.save();
    await _alerts.applySettings(settings);
  }

  Future<void> _testAlert() => _alerts.test(_settings);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: const Text('辅助设置'),
        ),
      ),
      body: !_loaded
          ? Semantics(
              label: '正在加载设置',
              child: const Center(child: CircularProgressIndicator()),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Semantics(
                  label: '语音预警，当前${_settings.voiceEnabled ? '已开启' : '已关闭'}',
                  toggled: _settings.voiceEnabled,
                  child: SwitchListTile(
                    value: _settings.voiceEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(voiceEnabled: value)),
                    secondary: const Icon(Icons.record_voice_over_rounded),
                    title: const Text('语音预警'),
                    subtitle: const Text('关闭后不再播报语音'),
                  ),
                ),
                Semantics(
                  label: '震动提醒，当前${_settings.vibrationEnabled ? '已开启' : '已关闭'}',
                  toggled: _settings.vibrationEnabled,
                  child: SwitchListTile(
                    value: _settings.vibrationEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(vibrationEnabled: value)),
                    secondary: const Icon(Icons.vibration_rounded),
                    title: const Text('震动提醒'),
                    subtitle: const Text('关闭后不再触发手机震动'),
                  ),
                ),
                Semantics(
                  button: true,
                  label: '测试当前提醒设置',
                  hint: '播放测试语音和震动',
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: FilledButton.icon(
                      onPressed: _testAlert,
                      icon: const Icon(Icons.campaign_rounded),
                      label: const Text('测试当前提醒设置'),
                    ),
                  ),
                ),
                _SettingSection(
                  title: '识别阈值',
                  icon: Icons.tune_rounded,
                  child: Semantics(
                    label: '识别阈值，当前${_settings.confidenceThreshold.toStringAsFixed(2)}',
                    value: _settings.confidenceThreshold.toStringAsFixed(2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Slider(
                          value: _settings.confidenceThreshold,
                          min: 0.25,
                          max: 0.85,
                          divisions: 12,
                          label: _settings.confidenceThreshold.toStringAsFixed(2),
                          onChanged: (value) => _save(
                            _settings.copyWith(confidenceThreshold: value),
                          ),
                        ),
                        Text(
                          '当前：${_settings.confidenceThreshold.toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ),
                ),
                _SettingSection(
                  title: '播报间隔',
                  icon: Icons.timer_rounded,
                  child: Semantics(
                    label: '播报间隔，当前${_settings.alertIntervalMs ~/ 1000 * 10 + (_settings.alertIntervalMs % 1000 / 100).round()}秒',
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 800, label: Text('0.8 秒')),
                        ButtonSegment(value: 1200, label: Text('1.2 秒')),
                        ButtonSegment(value: 1800, label: Text('1.8 秒')),
                      ],
                      selected: {_settings.alertIntervalMs},
                      onSelectionChanged: (values) => _save(
                        _settings.copyWith(alertIntervalMs: values.first),
                      ),
                    ),
                  ),
                ),
                Semantics(
                  label: '推理输入，固定640，当前模型输出8400个候选点',
                  child: const _SettingSection(
                    title: '推理输入',
                    icon: Icons.memory_rounded,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('640'),
                      subtitle: Text('当前模型固定输出 8400 个候选点'),
                      trailing: Icon(Icons.lock_rounded),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
