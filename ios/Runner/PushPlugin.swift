//
// PushPlugin.swift
//
// Native side of the 'omnihr/push' channel (push notifications,
// spec 2026-10-11 §6.1 / §6.4 / §6.5). Registered in AppDelegate next to
// FaceEmbedderPlugin. Dart wrapper: lib/services/push_native.dart.
//
// Channel contract:
//   - 'removeDelivered' { ids: [String] } — removes delivered
//     notifications by identifier. A remote notification's identifier is
//     its apns-collapse-id, which hrmsmanager sets to the push's omni_key.
//   - 'clearDelivered' — removes every delivered Omni HR notification
//     (the bell was opened).
//   - 'setBadge' { count: Int } — the app icon badge; iOS 16+ through
//     UNUserNotificationCenter.setBadgeCount, older through
//     applicationIconBadgeNumber.
// All calls answer nil; failures are silent (best effort).

import Flutter
import UIKit
import UserNotifications

class PushPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "omnihr/push",
            binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(PushPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let center = UNUserNotificationCenter.current()
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "removeDelivered":
            let ids = args?["ids"] as? [String] ?? []
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
            result(nil)
        case "clearDelivered":
            center.removeAllDeliveredNotifications()
            result(nil)
        case "setBadge":
            let count = max(0, args?["count"] as? Int ?? 0)
            if #available(iOS 16.0, *) {
                center.setBadgeCount(count) { _ in }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = count
                }
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
