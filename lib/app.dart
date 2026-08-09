import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_brand.dart';
import 'controllers/hub_controller.dart';
import 'screens/home_screen.dart';

ThemeData _buildTheme(Brightness brightness, Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
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

class McpHubApp extends StatefulWidget {
  const McpHubApp({super.key});

  @override
  State<McpHubApp> createState() => _McpHubAppState();
}

class _McpHubAppState extends State<McpHubApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _routeObserver = _HubNavigatorObserver();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_routeObserver],
      title: AppBrand.displayName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light, const Color(0xFF0F766E)),
      darkTheme: _buildTheme(Brightness.dark, const Color(0xFF2DD4BF)),
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
      },
      actions: <Type, Action<Intent>>{
        _EscapeIntent: CallbackAction<_EscapeIntent>(
          onInvoke: (_) {
            final navigator = _navigatorKey.currentState;
            if (_routeObserver.canPop && navigator != null) {
              navigator.pop();
            }
            return null;
          },
        ),
      },
      home: const HomeScreen(),
    );
  }
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _HubNavigatorObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  bool get canPop => _routes.length > 1;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
  }
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hub = HubController();
  await hub.load();
  runApp(ChangeNotifierProvider.value(value: hub, child: const McpHubApp()));
}
