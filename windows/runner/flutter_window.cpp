#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <algorithm>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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
    flutter_controller_.reset();
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "anigen/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "setFullscreen") {
          const auto* fullscreen = std::get_if<bool>(call.arguments());
          if (!fullscreen) {
            result->Error("bad-args", "expected a bool");
            return;
          }
          if (SetFullscreen(*fullscreen)) {
            result->Success();
          } else {
            result->Error("window-unavailable",
                          "could not change fullscreen state");
          }
        } else {
          result->NotImplemented();
        }
      });
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

bool FlutterWindow::SetFullscreen(bool fullscreen) {
  HWND window = GetHandle();
  if (!window) {
    return false;
  }
  if (fullscreen == fullscreen_) {
    return true;
  }

  if (fullscreen) {
    // Pick the monitor before restoring: a window maximized on another
    // monitor restores to wherever it was before it was maximized
    const HMONITOR target =
        ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!::GetMonitorInfo(target, &monitor) ||
        !::GetWindowPlacement(window, &placement_before_fullscreen_)) {
      return false;
    }

    // Restore a maximized window before removing its frame. Let the normal
    // DPI handler run during the restore, which can cross monitors.
    maximized_on_other_monitor_ = false;
    if (::IsZoomed(window)) {
      ::SendMessage(window, WM_SYSCOMMAND, SC_RESTORE, 0);
      maximized_on_other_monitor_ =
          ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST) != target;
      // Read size and DPI together after Windows has resized the normal window.
      RECT restored{};
      if (!::GetWindowRect(window, &restored)) {
        restored = placement_before_fullscreen_.rcNormalPosition;
      }
      normal_size_ = {restored.right - restored.left,
                      restored.bottom - restored.top};
      normal_dpi_ = FlutterDesktopGetDpiForHWND(window);
    }
    fullscreen_ = true;
    style_before_fullscreen_ = ::GetWindowLongPtr(window, GWL_STYLE);
    ex_style_before_fullscreen_ = ::GetWindowLongPtr(window, GWL_EXSTYLE);
    ::SetWindowLongPtr(window, GWL_STYLE,
                       style_before_fullscreen_ & ~(WS_CAPTION | WS_THICKFRAME));
    ::SetWindowLongPtr(window, GWL_EXSTYLE,
                       ex_style_before_fullscreen_ &
                           ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE |
                             WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));

    ::SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left,
                   monitor.rcMonitor.top,
                   monitor.rcMonitor.right - monitor.rcMonitor.left,
                   monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    // fullscreen_ stays true until the window is back in place, so a
    // WM_DPICHANGED from crossing monitors doesn't resize it a second time
    ::SetWindowLongPtr(window, GWL_STYLE, style_before_fullscreen_);
    ::SetWindowLongPtr(window, GWL_EXSTYLE, ex_style_before_fullscreen_);
    ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);

    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (maximized_on_other_monitor_ &&
        ::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                         &monitor)) {
      // Maximize on the monitor it's on now. Give it its old normal size,
      // centred there, so un-maximizing later doesn't fill the screen.
      const RECT& work = monitor.rcWork;
      const LONG work_width = work.right - work.left;
      const LONG work_height = work.bottom - work.top;
      // The normal size is in the old monitor's pixels; rescale it to this
      // monitor's DPI so it keeps the same apparent size
      const UINT dpi = FlutterDesktopGetDpiForHWND(window);
      const auto scaled_extent = [&](LONG size, LONG max_size) -> LONG {
        if (size <= 0) {
          return max_size;
        }
        const LONG scaled =
            dpi > 0 && normal_dpi_ > 0
                ? ::MulDiv(size, static_cast<int>(dpi),
                           static_cast<int>(normal_dpi_))
                : size;
        return scaled > 0 ? std::min<LONG>(scaled, max_size) : max_size;
      };
      const LONG width = scaled_extent(normal_size_.cx, work_width);
      const LONG height = scaled_extent(normal_size_.cy, work_height);
      ::SetWindowPos(window, nullptr, work.left + (work_width - width) / 2,
                     work.top + (work_height - height) / 2, width, height,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      ::ShowWindow(window, SW_MAXIMIZE);
    } else {
      // Puts it back where it was, maximized again if it was
      ::SetWindowPlacement(window, &placement_before_fullscreen_);
    }
    maximized_on_other_monitor_ = false;
    fullscreen_ = false;
  }
  return true;
}

void FlutterWindow::OnDestroy() {
  fullscreen_ = false;
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
    window_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_DPICHANGED:
      // In fullscreen, don't let the default handler resize the window away
      // from the monitor's bounds. The size stays the same, so nudge the
      // Flutter view to resend its metrics with the new scale.
      if (fullscreen_) {
        if (flutter_controller_ && flutter_controller_->view()) {
          const HWND view = flutter_controller_->view()->GetNativeWindow();
          RECT client{};
          if (::GetClientRect(view, &client)) {
            ::SendMessage(view, WM_SIZE, SIZE_RESTORED,
                          MAKELPARAM(client.right - client.left,
                                     client.bottom - client.top));
          }
        }
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
