import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 写入资源压缩包内的上传元数据（不进入解压后的 Skill/Command/Rule 目录）。
class ZipPackageMeta {
  const ZipPackageMeta({required this.uploadedAt});

  static const dirName = '__mcp_hub__';
  static const entryName = '$dirName/package.json';

  final DateTime uploadedAt;

  Map<String, dynamic> toJson() => {
        'uploadedAt': uploadedAt.toUtc().toIso8601String(),
      };

  factory ZipPackageMeta.fromJson(Map<String, dynamic> json) {
    final parsed = DateTime.tryParse(json['uploadedAt'] as String? ?? '');
    return ZipPackageMeta(
      uploadedAt: parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  List<int> toUtf8Json() =>
      utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson()));

  static bool isReservedEntry(String relativePath) {
    final name = relativePath.replaceAll('\\', '/');
    return name == entryName || name.startsWith('$dirName/');
  }

  static ZipPackageMeta? fromArchiveBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name != entryName && !name.endsWith('/$entryName')) continue;
      final decoded = jsonDecode(utf8.decode(file.content as List<int>));
      if (decoded is Map<String, dynamic>) {
        return ZipPackageMeta.fromJson(decoded);
      }
      if (decoded is Map) {
        return ZipPackageMeta.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    }
    return null;
  }
}
