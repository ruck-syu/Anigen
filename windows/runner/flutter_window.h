#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Fullscreen for the player. media_kit's own leaves the title bar on a
  // maximized window, so the app does it here instead.
  bool SetFullscreen(bool fullscreen);
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;
  bool fullscreen_ = false;
  LONG_PTR style_before_fullscreen_ = 0;
  LONG_PTR ex_style_before_fullscreen_ = 0;
  WINDOWPLACEMENT placement_before_fullscreen_{sizeof(WINDOWPLACEMENT)};
  // Maximized onto a different monitor than its normal position, so exiting
  // should maximize it where it is rather than where it used to be.
  bool maximized_on_other_monitor_ = false;
  // The restored size and its DPI, to rescale the size for another monitor.
  SIZE normal_size_{};
  UINT normal_dpi_ = USER_DEFAULT_SCREEN_DPI;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
