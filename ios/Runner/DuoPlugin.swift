//
// DuoPlugin.swift
//
// Native side of the 'omnihr/duo' channel: what Flutter cannot see on
// iPhone Duo (iOS 27.1). Flutter fills MediaQuery.displayFeatures only on
// Android, so on iOS the fold and the inner FaceTime camera are invisible
// to Dart. This plugin reads them from UIKit and sends them over. Dart
// wrapper: lib/services/duo_service.dart.
//
// Sources (iOS 27.1 SDK):
//   - UIView.reservedRegions(kind: .division, options: .includeInactive):
//     the fold. Active (with a width) only while the phone is half-folded;
//     flat it is inactive with zero width.
//   - UIView.reservedRegions(kind: .occlusion, options: .includeInactive):
//     the inner FaceTime camera; active while that camera is in use.
//   - UIHingeInteraction: hinge status (closed / partiallyOpen / fullyOpen)
//     and angle.
//   - UIView.edgeInsets(for: .bar(onEdge:extent:)): where a 48 pt vertical
//     bar may sit on the left / right edge, below the status stack and
//     camera, centred on the camera. Measured on the 27.1 simulator: closed
//     (466 × 678) right bar = (394, 170, 48, 474); open sideways (951 × 669)
//     = (879, 120, 48, 515). Our column buttons and tabs follow it.
// Frames are in the Flutter view's coordinates (points = Flutter logical
// pixels) and include the system's margins for interactive content.
//
// Channel contract:
//   - 'start' → snapshot. Attaches an invisible observer view to the
//     Flutter view (lazily: the implicit engine has no view at
//     registration) and starts sending 'changed'.
//   - 'get' → snapshot (e.g. when the camera opens: the occlusion region
//     has no change callback).
//   - Native → Dart 'changed' snapshot, only when it differs from the
//     last one sent. Re-read on the observer's layout (fold, unfold,
//     rotation, split view) and on every hinge update.
// Snapshot: { available: Bool, hinge: 'none'|'unknown'|'closed'|
//   'partiallyOpen'|'fullyOpen', angle: Double (radians, -1 when none),
//   divisions: [[x, y, w, h, active(0|1)]], occlusions: [[…same…]],
//   barLeft: [x, y, w, h], barRight: [x, y, w, h] }.
// Before iOS 27.1 every call answers { available: false, … } and nothing
// is observed.

import Flutter
import UIKit

class DuoPlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel
    private var observer: DuoObserverView?
    private var hingeStatus = "none"
    private var hingeAngle: Double = -1
    private var lastSent: [String: Any]?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "omnihr/duo",
            binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(DuoPlugin(channel: channel), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            attachIfNeeded()
            let snap = snapshot()
            lastSent = snap
            result(snap)
        case "get":
            result(snapshot())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// The Flutter view: the key window's root view controller.
    private func hostView() -> UIView? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first
            if let view = window?.rootViewController?.view { return view }
        }
        return nil
    }

    private func attachIfNeeded() {
        guard observer == nil, let host = hostView() else { return }
        let view = DuoObserverView(frame: host.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        view.onLayout = { [weak self] in self?.sendIfChanged() }
        host.addSubview(view)
        observer = view
        if #available(iOS 27.1, *) {
            let hinge = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                if let h = update.hinge {
                    self.hingeStatus = DuoPlugin.name(of: h.status)
                    self.hingeAngle = Double(h.angle)
                } else {
                    self.hingeStatus = "none"
                    self.hingeAngle = -1
                }
                self.sendIfChanged()
            }
            view.addInteraction(hinge)
        }
    }

    @available(iOS 27.1, *)
    private static func name(of status: UIHinge.Status) -> String {
        switch status {
        case .closed: return "closed"
        case .partiallyOpen: return "partiallyOpen"
        case .fullyOpen: return "fullyOpen"
        default: return "unknown"
        }
    }

    private func snapshot() -> [String: Any] {
        var snap: [String: Any] = [
            "available": false,
            "hinge": hingeStatus,
            "angle": hingeAngle,
            "divisions": [[Double]](),
            "occlusions": [[Double]](),
        ]
        guard #available(iOS 27.1, *), let view = observer ?? hostView() else {
            return snap
        }
        snap["available"] = true
        snap["divisions"] = DuoPlugin.encode(
            view.reservedRegions(kind: .division, options: .includeInactive))
        snap["occlusions"] = DuoPlugin.encode(
            view.reservedRegions(kind: .occlusion, options: .includeInactive))
        snap["barLeft"] = DuoPlugin.bar(in: view, edge: .left)
        snap["barRight"] = DuoPlugin.bar(in: view, edge: .right)
        return snap
    }

    /// The frame a vertical bar of our button size (48 pt) gets on [edge].
    @available(iOS 27.1, *)
    private static func bar(in view: UIView, edge: UIRectEdge) -> [Double] {
        let f = view.bounds.inset(
            by: view.edgeInsets(for: .bar(onEdge: edge, extent: 48)))
        return [Double(f.origin.x), Double(f.origin.y),
                Double(f.size.width), Double(f.size.height)]
    }

    @available(iOS 27.1, *)
    private static func encode(_ regions: [UIView.ReservedRegion]) -> [[Double]] {
        regions.map { r in
            [Double(r.frame.origin.x), Double(r.frame.origin.y),
             Double(r.frame.size.width), Double(r.frame.size.height),
             r.isActive ? 1 : 0]
        }
    }

    private func sendIfChanged() {
        let snap = snapshot()
        if let last = lastSent, NSDictionary(dictionary: last).isEqual(to: snap) {
            return
        }
        lastSent = snap
        channel.invokeMethod("changed", arguments: snap)
    }
}

/// Invisible, full-size view on top of the Flutter view: its layout runs
/// whenever the window changes size (fold, unfold, rotation, split view).
final class DuoObserverView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}
