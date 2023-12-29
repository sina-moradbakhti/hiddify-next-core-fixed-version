import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // https://github.com/leanflutter/window_manager/issues/214
    return false
  }

  // // window manager restore from dock: https://leanflutter.dev/blog/click-dock-icon-to-restore-after-closing-the-window
  // override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  //     if !flag {
  //         for window in NSApp.windows {
  //             if !window.isVisible {
  //                 window.setIsVisible(true)
  //             }
  //             window.makeKeyAndOrderFront(self)
  //             NSApp.activate(ignoringOtherApps: true)
  //         }
  //     }
  //     return true
  // }
}
