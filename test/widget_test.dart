import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home shows Agent Hub title', (tester) async {
    final hub = HubController();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: hub,
        child: const McpHubApp(),
      ),
    );
    await tester.pump();
    expect(find.text(AppBrand.displayName), findsOneWidget);
    expect(find.text('添加 MCP'), findsOneWidget);
  });
}
