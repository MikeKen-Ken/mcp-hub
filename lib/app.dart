import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/hub_controller.dart';
import 'screens/home_screen.dart';

class McpHubApp extends StatelessWidget {
  const McpHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2DD4BF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
