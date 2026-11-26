import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_brand.dart';
import 'common/app_locale.dart';
import 'common/app_theme.dart';
import 'common/app_theme_mode.dart';
import 'controllers/hub_controller.dart';
import 'screens/home_screen.dart';

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
    return ListenableBuilder(
      listenable: Listenable.merge([AppLocale.notifier, AppThemeMode.notifier]),
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        navigatorObservers: [_routeObserver],
        title: AppBrand.displayName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: AppThemeMode.current.themeMode,
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
      ),
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
  await AppLocale.load();
  await AppThemeMode.load();
  final hub = HubController();
  runApp(ChangeNotifierProvider.value(value: hub, child: const McpHubApp()));
  await hub.load();
}
