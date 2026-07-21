import 'package:flutter/material.dart';

import 'features/home/home_page.dart';
import 'features/settings/settings_page.dart';
import 'theme/app_theme.dart';

// AI辅助生成：Codex.2026-03-18) 搭建应用路由和全局主题入口。
class VisionGuardApp extends StatelessWidget {
  const VisionGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '离线视觉辅助',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routes: {
        '/': (_) => const HomePage(),
        SettingsPage.routeName: (_) => const SettingsPage(),
      },
    );
  }
}
