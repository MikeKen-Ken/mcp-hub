import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

CallToolResult mcpJsonResult(Object data) {
  return CallToolResult(
    content: [
      TextContent(text: const JsonEncoder.withIndent('  ').convert(data)),
    ],
  );
}

CallToolResult mcpErrorResult(String message) {
  return CallToolResult(
    isError: true,
    content: [TextContent(text: message)],
  );
}

String? mcpTrimmedString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool mcpBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}

List<String> mcpStringList(Object? value) {
  if (value is List) {
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, String> mcpStringMap(Object? value) {
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );
  }
  return const {};
}
