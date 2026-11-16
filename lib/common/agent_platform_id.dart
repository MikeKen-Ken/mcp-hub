/// 已登记的 AI 客户端平台标识。
///
/// 平台元数据与能力见 [AgentPlatforms]（`agent_platforms.dart`）。
enum AgentPlatformId {
  cursor,
  codex,
  openCode,

  /// WorkBuddy 国内版（`~/.workbuddy`）。
  workBuddy,

  /// WorkBuddy AI 国际版（`~/.workbuddy-ai`）。
  workBuddyAi,

  /// DeepSeek Harness（`$DSH_HOME`，默认 `~/.dsh`）。
  deepSeekHarness,

  /// 豆包电脑版（工作任务的本地技能目录，无本地 MCP 配置文件）。
  doubao,

  /// Google Antigravity（`~/.gemini/config`）。
  antigravity,
}
