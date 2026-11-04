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
}
