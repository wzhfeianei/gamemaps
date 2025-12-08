import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register screen capture method channel
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let screenCaptureChannel = FlutterMethodChannel(name: "com.gamemaps/screen_capture", binaryMessenger: controller.binaryMessenger)
    screenCaptureChannel.setMethodCallHandler {
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      switch call.method {
      case "captureScreen":
        self.captureScreen(result: result)
      case "captureWindow":
        result(FlutterError(code: "NOT_SUPPORTED", message: "Window capture is not supported on iOS", details: nil))
      case "getRunningWindows":
        result([])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func captureScreen(result: @escaping FlutterResult) {
    guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
      result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to get key window", details: nil))
      return
    }
    
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, false, UIScreen.main.scale)
    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    
    guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
      UIGraphicsEndImageContext()
      result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to capture screen", details: nil))
      return
    }
    
    UIGraphicsEndImageContext()
    
    // Convert UIImage to PNG data
    guard let pngData = image.pngData() else {
      result(FlutterError(code: "CAPTURE_FAILED", message: "Failed to convert image to PNG", details: nil))
      return
    }
    
    // Return PNG data to Flutter
    result(pngData)
  }
}
