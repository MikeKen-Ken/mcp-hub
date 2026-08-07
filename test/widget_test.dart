import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home shows MCP Hub title', (tester) async {
    final hub = HubController();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: hub,
        child: const McpHubApp(),
      ),
    );
    await tester.pump();
    expect(find.text('MCP Hub'), findsOneWidget);
    expect(find.text('添加 MCP'), findsOneWidget);
  });
}
