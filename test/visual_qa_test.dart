import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:provider/provider.dart';

Future<void> _capture(GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/visual_qa/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('capture redesigned navigation', (tester) async {
    tester.view.physicalSize = const Size(960, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey();
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ChangeNotifierProvider.value(
          value: hub,
          child: const McpHubApp(),
        ),
      ),
    );
    await tester.pump();
    await _capture(key, 'home');

    await tester.tap(find.text('Agent 配置下载/上传'));
    await tester.pumpAndSettle();
    await _capture(key, 'sync');
  });
}
