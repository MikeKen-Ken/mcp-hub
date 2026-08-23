import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/app_motion.dart';

void main() {
  testWidgets('motion is disabled when the platform requests reduced motion', (
    tester,
  ) async {
    late Duration resolvedDuration;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolvedDuration = AppMotion.durationOf(
                context,
                AppMotion.standard,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(resolvedDuration, Duration.zero);
  });
}
