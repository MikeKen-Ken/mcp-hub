import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_brand.dart';
import 'controllers/hub_controller.dart';
import 'screens/home_screen.dart';

ThemeData _buildTheme(Brightness brightness, Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
  );

  // 统一字重：标题/标签用 w500，正文用 w400，避免中文环境下 w400/w500/w600 混用发虚。
  final textTheme = base.textTheme.copyWith(
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
    titleMedium:
        base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
    labelMedium:
        base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
    labelSmall: base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: AppBarTheme(
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      toolbarTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

class McpHubApp extends StatelessWidget {
  const McpHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.displayName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light, const Color(0xFF0F766E)),
      darkTheme: _buildTheme(Brightness.dark, const Color(0xFF2DD4BF)),
      home: const HomeScreen(),
    );
  }
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hub = HubController();
  await hub.load();
  runApp(
    ChangeNotifierProvider.value(
      value: hub,
      child: const McpHubApp(),
    ),
  );
}
