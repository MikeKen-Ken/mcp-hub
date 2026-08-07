import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows storage identity stays stable across display-name changes', () {
    final runnerResource = File('windows/runner/Runner.rc').readAsStringSync();

    expect(
      runnerResource,
      contains('VALUE "ProductName", "mcp_hub" "\\0"'),
      reason: 'path_provider derives the application-support directory from '
          'CompanyName and ProductName, so changing ProductName hides existing '
          'shared_preferences such as the WebDAV configuration.',
    );
    expect(
      runnerResource,
      contains('VALUE "FileDescription", "Agent Hub" "\\0"'),
      reason: 'The user-facing Windows description can remain Agent Hub.',
    );
  });
}
