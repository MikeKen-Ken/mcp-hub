#include "flutter_window.h"

#include <cmath>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <flutter_windows.h>

namespace {
constexpr wchar_t kWindowSettingsKey[] = L"Software\\Agent Hub";
constexpr wchar_t kWindowWidthValue[] = L"WindowWidth";
constexpr wchar_t kWindowHeightValue[] = L"WindowHeight";
constexpr DWORD kMinimumWindowWidth = 400;
constexpr DWORD kMinimumWindowHeight = 300;
constexpr DWORD kMaximumWindowWidth = 7680;
constexpr DWORD kMaximumWindowHeight = 4320;

bool ReadWindowDimension(const wchar_t* value_name, DWORD* value) {
  DWORD value_size = sizeof(*value);
  return RegGetValue(HKEY_CURRENT_USER, kWindowSettingsKey, value_name,
                     RRF_RT_REG_DWORD, nullptr, value, &value_size) ==
         ERROR_SUCCESS;
}

bool IsValidWindowSize(DWORD width, DWORD height) {
  return width >= kMinimumWindowWidth && width <= kMaximumWindowWidth &&
         height >= kMinimumWindowHeight && height <= kMaximumWindowHeight;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

Win32Window::Size FlutterWindow::LoadSavedSize(
    const Win32Window::Size& fallback) {
  DWORD width = 0;
  DWORD height = 0;
  if (!ReadWindowDimension(kWindowWidthValue, &width) ||
      !ReadWindowDimension(kWindowHeightValue, &height) ||
      !IsValidWindowSize(width, height)) {
    return fallback;
  }
  return Win32Window::Size(width, height);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE) {
    SaveWindowSize(hwnd);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SaveWindowSize(HWND window) const {
  WINDOWPLACEMENT placement = {sizeof(placement)};
  if (!GetWindowPlacement(window, &placement)) {
    return;
  }

  const RECT& rect = placement.rcNormalPosition;
  const auto width = rect.right - rect.left;
  const auto height = rect.bottom - rect.top;
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const DWORD logical_width = static_cast<DWORD>(std::lround(width / scale));
  const DWORD logical_height = static_cast<DWORD>(std::lround(height / scale));
  if (!IsValidWindowSize(logical_width, logical_height)) {
    return;
  }

  RegSetKeyValue(HKEY_CURRENT_USER, kWindowSettingsKey, kWindowWidthValue,
                 REG_DWORD, &logical_width, sizeof(logical_width));
  RegSetKeyValue(HKEY_CURRENT_USER, kWindowSettingsKey, kWindowHeightValue,
                 REG_DWORD, &logical_height, sizeof(logical_height));
}
