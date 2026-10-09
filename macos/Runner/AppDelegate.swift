import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  /// Whether this process was started as a login item. Best effort: it is
  /// derived from the launch Apple event, which is only available while the
  /// open-application event is being handled. It is evaluated in
  /// applicationWillFinishLaunching and, lazily, from the window ordering
  /// override; the first non-nil answer is cached.
  ///
  /// Reliability: `keyAELaunchedAsLogInItem` is set by launchd/loginwindow for
  /// classic login items. For SMAppService.mainApp launches on macOS 13+ it is
  /// not documented and may be absent; treat `false` as "unknown".
  static var launchedAtLogin: Bool {
    if let cached = cachedLaunchedAtLogin { return cached }
    guard let event = NSAppleEventManager.shared().currentAppleEvent else {
      return false
    }
    let isOpenApp = event.eventID == AEEventID(kAEOpenApplication)
    var result = false
    if isOpenApp,
      let param = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
    {
      result = param.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
    cachedLaunchedAtLogin = result
    return result
  }
  private static var cachedLaunchedAtLogin: Bool?

  /// Held for the app's lifetime and never ended. App Nap throttles timers of
  /// a hidden app, and the reminder heartbeat must run on time. Idle system
  /// sleep stays allowed (the heartbeat's wall-clock catch-up handles sleep).
  private var activityToken: NSObjectProtocol?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    _ = AppDelegate.launchedAtLogin
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    activityToken = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "Knight Rise delivers timed break reminders")
    super.applicationDidFinishLaunching(notification)
  }

  // Close-to-tray: the Dart side hides the window; quitting is explicit.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
