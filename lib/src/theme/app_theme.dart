import 'package:flutter/material.dart';

// AI辅助生成：Codex.2026-03-20) 定义深色高对比主题，适配户外实时辅助场景。
ThemeData buildAppTheme() {
  const seed = Color(0xff0b6e69);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xff101615),
    ),
    scaffoldBackgroundColor: const Color(0xff07100f),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(height: 1.35),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xff13201f),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
