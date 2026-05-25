import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Custom face-embedder plugin. Bridges Dart to TFLite via the
    // Swift TensorFlowLiteSwift API — bypassing dart:ffi/dlsym
    // which Apple's iOS 26 release-build linker dead-strips.
    // See ios/Runner/FaceEmbedderPlugin.swift for full context.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FaceEmbedderPlugin") {
      FaceEmbedderPlugin.register(with: registrar)
    }
  }
}
