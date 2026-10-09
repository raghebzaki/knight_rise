import Cocoa
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // The splash background (KnightPalette.midnight #0A1020) until Flutter's first frame, instead of the system
    // window colour, so the window opens straight into the AnimatedSplash colours.
    let launchBackground = NSColor(srgbRed: 0x0A / 255.0, green: 0x10 / 255.0, blue: 0x20 / 255.0, alpha: 1)
    flutterViewController.backgroundColor = launchBackground
    self.backgroundColor = launchBackground
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerDesktopChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Start hidden when launched at login so the window never flashes. The flag
  // is read lazily here as well, in case the nib window is ordered before
  // applicationWillFinishLaunching has captured it.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    if AppDelegate.launchedAtLogin {
      hiddenWindowAtLaunch()
    }
  }

  private static func statusString(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: return "enabled"
    case .notRegistered: return "notRegistered"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "notFound"
    }
  }

  private func registerDesktopChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "knight_rise/desktop", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let service = SMAppService.mainApp
      switch call.method {
      case "launchAtLoginStatus":
        result(MainFlutterWindow.statusString(service.status))
      case "setLaunchAtLogin":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? false
        do {
          if enabled {
            if service.status != .enabled { try service.register() }
          } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
          }
          result(MainFlutterWindow.statusString(service.status))
        } catch {
          result(FlutterError(
            code: "launch_at_login_failed",
            message: error.localizedDescription, details: nil))
        }
      case "openLoginItemsSettings":
        SMAppService.openSystemSettingsLoginItems()
        result(nil)
      case "appNapDisabled":
        result((NSApp.delegate as? AppDelegate)?.appNapDisabled ?? false)
      case "launchedAtLogin":
        result(AppDelegate.launchedAtLogin)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
