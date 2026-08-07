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
    // Noto Sans SC keeps the stroke density of small Simplified Chinese labels
    // more even than the Windows fallback font. It also contains Latin glyphs,
    // so mixed labels do not switch font halfway through a line.
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const <String>[
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Segoe UI',
      'sans-serif',
    ],
  );

  // Use the real regular face throughout. Size still provides hierarchy.
  final textTheme = base.textTheme.copyWith(
    displayLarge: base.textTheme.displayLarge?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    displayMedium: base.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    displaySmall: base.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w400,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
    ),
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
