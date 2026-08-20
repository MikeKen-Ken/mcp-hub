import 'skill_target.dart';

enum SkillSyncStatus { idle, syncing, success, error }

/// 一次 Skill / Agent 资源下载、上传或转换的结果摘要。
class SkillSyncResult {
  const SkillSyncResult({
    required this.ok,
    required this.message,
    this.target,
    this.pulledFiles = 0,
    this.pushedFiles = 0,
    this.deployedFiles = 0,
    this.packageCount = 0,
  });
  final bool ok;
  final String message;
  final SkillTarget? target;
  final int pulledFiles;
  final int pushedFiles;
  final int deployedFiles;
  final int packageCount;
}
