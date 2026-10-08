import Flutter
import UIKit
import UserNotifications
// Required for FlutterLocalNotificationsPlugin.setPluginRegistrantCallback.
import flutter_local_notifications
// Required for WorkmanagerPlugin.
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: show notifications / deliver actions via the plugin.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    // workmanager: BGTaskScheduler launch handlers must be registered before
    // didFinishLaunching returns. With the UIScene lifecycle the plugin registers
    // later, so re-register previously scheduled tasks here (workmanager_apple docs).
    WorkmanagerPlugin.registerLaunchHandlers()
    // Hourly BGAppRefresh reconcile; identifier must match BGTaskSchedulerPermittedIdentifiers
    // and the unique name used from Dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.ragheb.knightRise.reconcile",
      earliestBeginInSeconds: 60 * 60
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Lets notification-action / background isolates use all plugins.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Lets workmanager's background engine use all plugins.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Device health channel (see lib/features/device_health/data). The application
    // registrar of the implicit engine provides the binary messenger.
    let healthChannel = FlutterMethodChannel(
      name: "knight_rise/device_health",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    healthChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "backgroundRefreshStatus":
        DispatchQueue.main.async {
          switch UIApplication.shared.backgroundRefreshStatus {
          case .available: result("available")
          case .denied: result("denied")
          case .restricted: result("restricted")
          @unknown default: result("available")
          }
        }
      case "openAppSettings":
        DispatchQueue.main.async {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
          } else {
            result(false)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
