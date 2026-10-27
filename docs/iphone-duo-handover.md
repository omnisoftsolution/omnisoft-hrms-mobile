# iPhone Duo — developer handover

Everything learned while making the Omni HR Flutter app iPhone Duo compatible (Oct 2026). Written so another
project, on another machine, can start from here. Nothing in this file is specific to Omni HR except the
examples.

**Trust levels used below**

- **[measured]**: read from the iOS 27.1 simulator (Xcode 27.1, build 27A9275, runtime 24A94232) with a probe
  that logged the values from inside a running app.
- **[SDK]**: read from the iOS 27.1 SDK headers or `.swiftinterface`.
- **[talk]**: from Apple's iPhone Duo tech talks (111461 *Prepare your app*, 111462 *bars*, 111463
  *poses / reserved regions*, 111464 *hinge / scenes*, 111466 *design*). Not re-checked in code.

---

## 1. The device in numbers

| State | Logical size (pt) | Pixels (@3x) | What iOS reserves |
|---|---|---|---|
| Closed (cover display), portrait | 466 × 678 | 1398 × 2034 | 84 pt **vertical bar on the right** (camera, clock, status), safe area `right 84, bottom 34` [measured] |
| Closed, held sideways | 678 × 466 | 2034 × 1398 | the vertical bar moves to the **left** (camera side) [measured] |
| Open (inner display), upright | 669 × 951 | 2007 × 2853 | ordinary top status bar, safe area `top 82, bottom 34`, **no vertical bar** [measured] |
| Open, sideways | 951 × 669 | 2853 × 2007 | 84 pt vertical bar on the right, safe area `right 84, bottom 34` [measured] |

- In split view the app can get its vertical bar on the **left** [talk]. Treat left and right the same way.
- The inner display **ignores portrait lock**, so your app *will* run sideways there even if it is portrait-only
  on other iPhones [talk]. Size classes on the inner display are regular / regular (iPad-like) [talk].
- The cover display is a normal iPhone width class (compact).

### Where the vertical bar's content may go [measured]

`view.edgeInsets(for: .bar(onEdge:extent:))` (iOS 27.1) gives the frame a vertical bar of a given width gets:
below the status stack and camera, above the home indicator, centred on the camera. For a **48 pt** bar:

| State | Right-edge bar frame (x, y, w, h) | Notes |
|---|---|---|
| Closed portrait (466 × 678) | (394, **170**, 48, 474) | centre x = 418 = camera centre, not the column centre (424) |
| Open sideways (951 × 669) | (879, **120**, 48, 515) | no camera in the column here, so it starts higher |
| Open upright (669 × 951) | `top 82` (no vertical bar in this pose) | `traitCollection.verticalBarEdge` = unspecified |

**Lesson:** the top of the usable column differs per pose (170 vs 120 pt). Never hard-code it; ask UIKit.

### The fold ("division" reserved region) [measured]

| Pose | Division frame | Active |
|---|---|---|
| Flat (fully open) | zero width | no |
| Half-open, sideways (**book** pose, vertical fold) | (455.5, 0, 40, 669) | yes |
| Half-open, upright (**desk / laptop** pose, horizontal fold) | (0, 455.5, 669, 40) | yes |

- The hinge angle is reported in radians: about 2.2 (≈128°) when "Partially Open" in the simulator, rising to
  about 3.05 as it opens.
- `UIHinge.Status` is one of `unknown`, `closed`, `partiallyOpen` or `fullyOpen`.

### Occlusions [measured]

- **Inner FaceTime camera:** for example (677, 21, 58, 37) sideways and (21, 215.7, 37, 58) upright. Inactive
  unless that camera is in use.
- **Status stack:** reported as an *active* occlusion, for example (867, 0, 84, 120) sideways and
  (535, 0, 134, 82) upright. Its height matches the bar's top inset.

---

## 2. Apple's rules (HIG for iPhone Duo) [talk]

1. **The vertical bar.** On the closed phone, and on the open phone held sideways, bars move into the side
   column:
   - tab bars sit at the **bottom** of the column (near the thumb);
   - **icon** toolbar and navigation buttons (back, close, bell, profile, share…) stack at the **top**,
     under the status;
   - **text** buttons, titles, search fields and segmented controls stay in the content (horizontal).
2. **Open upright** behaves like a big iPhone: status on top, tab bar at the bottom.
3. **Split view:** the column can be on the left. Mirror everything.
4. **Half-folded:**
   - Never put content or controls *in* the fold.
   - **Book pose** (sideways, vertical fold): use the two halves as two pages.
   - **Desk pose** (upright, horizontal fold): interactive controls go in the **bottom** (flat, stable) half;
     the top half is for viewing (camera, video, preview).
5. **Layout:**
   - Design for **size classes**, not fixed widths.
   - When a fold exists, prefer an **even** number of columns, so no column straddles the fold.
6. **Sheets** on the cover display stop short of the camera when the vertical bar is disabled.
7. **Dialogs / popovers** should anchor on the trailing side; keep them off the fold.

---

## 3. iOS 27.1 SDK surface [SDK]

All of these need `#available(iOS 27.1, *)`. Everything is in UIKit.

| API | What it gives you |
|---|---|
| `UIView.reservedRegions(kind: .division / .occlusion, options: .includeInactive) -> [UIView.ReservedRegion]` | fold and camera / status frames; `ReservedRegion` has `frame`, `isActive`, `kind`, `id` |
| `UIHingeInteraction { interaction, update in update.hinge?.status / .angle }` (add it to any view) | hinge status and angle, live |
| `UIView.LayoutRegion.bar(onEdge: UIRectEdge \| NSDirectionalRectEdge, extent: CGFloat)` + `view.edgeInsets(for:)` / `directionalEdgeInsets(for:)` / `layoutGuide(for:)` | the frame a custom vertical bar should use (section 1) |
| `UITraitCollection.verticalBarEdge` → `UIVerticalBarEdge` `.unspecified / .leading / .trailing`; `systemTraitsAffectingVerticalBarEdge` (register for trait changes) | which edge the system puts the vertical bar on |
| `UIViewController.preferredVerticalBarBehavior` → `UIVerticalBarBehavior` `.automatic / .disabled`; `childForPreferredVerticalBarBehavior`; `setNeedsUpdateOfVerticalBarConfiguration()` | **opt a screen (or the whole app) out of the vertical bar**: bars fall back to top/bottom and the status bar goes horizontal again |
| `UIBarButtonItem.axisBehavior` → `.automatic / .horizontalOnly / .verticalPreferred` | keep an item horizontal, or prefer it in the vertical bar |
| `UINavigationItem.verticalBarCompressionBehavior` → `.automatic / .prefersBarItems / .prefersTabBar` | what compresses first when tabs and items share the vertical bar |
| `UIArrangementViewController`, `UISplitArrangement`, `UIOverlayArrangement` | the system's two-pane / overlay containers (book layouts, split view) |
| `UISceneAccessory.cameraCapture(sceneConfiguration:)`, scene role `.windowCameraCaptureAccessory` | extra scene shown while your camera session runs (e.g. a preview on the cover display) |

**Native UIKit / SwiftUI apps get most of the bar behaviour for free.** `UITabBarController`,
`UINavigationController`, toolbars and SwiftUI `TabView` / `.toolbar` move into the vertical bar by themselves.
The work left is: fold-aware layouts, size classes, and the `axisBehavior` of individual items.

---

## 4. Cross-platform apps (Flutter, React Native, Unity…): the real work

These frameworks draw their own bars, so **nothing moves by itself**. Here is what the Omni HR app needed.

### 4.0 The cheap option first: opt out

Return `.disabled` from `preferredVerticalBarBehavior` on the root view controller (for Flutter, a
`FlutterViewController` subclass). This is in the SDK header and was *not* tried in Omni HR. iOS then gives the
app a normal horizontal status bar on the cover display, and your usual top/bottom layout works.

This is a fast way to be "compatible". It is not "designed for Duo". Still handle the fold (4.3) and sideways
running.

### 4.1 Detect the column

- The safe area reports the column as a wide, lopsided side inset: `viewPadding.right ≈ 84` (or left).
- A normal iPhone held sideways has insets on *both* sides (notch on one side, a mirror inset on the other). So
  treat it as the column only when one side is ≥ 60 and `|left − right| ≥ 40`.
- Better still: also read `verticalBarEdge` over the bridge.

### 4.2 Lay the app out beside the column

- Wrap the whole app (Flutter: `MaterialApp.builder`) in a host that puts the app in an `Expanded` next to a
  column of that width. Remove that side's padding for the app.
- **Shift `displayFeatures` by −width when the column is on the left**, or fold maths is off by 84 pt.
- Keep **the same widget tree shape** with and without the column (and folded or not). Otherwise folding or
  unfolding rebuilds the app's Navigator and loses every pushed page.
  - *Bug we had:* `return extra.isEmpty ? child : MediaQuery(child: child)` remounted the whole app the moment
    a fold appeared.
- Draw your tabs as a vertical pill at the **bottom** of the column, and your icon buttons (back / bell /
  profile) at the **top**. Position both from the system's bar frame (4.4), not constants.
- Screens offer their buttons to the column only while they are on top:
  - Flutter: `TickerMode.valuesOf(context).enabled && ModalRoute.of(context)?.isCurrent`.
  - Withdraw them on dispose.
- **Hide the tabs while a full-screen page covers the shell** (root-navigator route, root sheet). On a phone
  that page covers the bottom bar. In the column, the tabs would otherwise stay tappable over it.
- Widgets drawn in the column sit above the app's Navigator, so there is **no Overlay**: no `Tooltip`. Use
  `Semantics` labels instead.

### 4.3 The fold: Flutter gets nothing on iOS

`MediaQuery.displayFeatures` is filled only on Android. On iOS it is **always empty**, so you need a native
bridge.

**Swift plugin (`omnihr/duo` channel), essentials:**

```swift
// Find the Flutter view lazily: with the implicit engine there is no view at plugin registration.
let host = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController?.view

// Invisible full-size observer: its layoutSubviews fires on fold, unfold, rotation and split view.
final class DuoObserverView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
    override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? { nil }  // never steal touches
}
// view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; host.addSubview(view)

if #available(iOS 27.1, *) {
    view.addInteraction(UIHingeInteraction { _, update in
        status = update.hinge?.status; angle = update.hinge?.angle; sendIfChanged()
    })
    let divisions  = view.reservedRegions(kind: .division,  options: .includeInactive)
    let occlusions = view.reservedRegions(kind: .occlusion, options: .includeInactive)
    let barRight = view.bounds.inset(by: view.edgeInsets(for: .bar(onEdge: .right, extent: 48)))
    let barLeft  = view.bounds.inset(by: view.edgeInsets(for: .bar(onEdge: .left,  extent: 48)))
}
// Send a snapshot only when it differs from the last one (NSDictionary isEqual).
// Snapshot: { available, hinge, angle, divisions: [[x,y,w,h,active]], occlusions: [...],
//             barLeft: [x,y,w,h], barRight: [x,y,w,h] }; available = false before iOS 27.1.
```

- Register it in `AppDelegate` the same way as any other in-app plugin.
- Add the `.swift` file to the Runner target. With a hand-edited `project.pbxproj` you need four entries:
  `PBXBuildFile`, `PBXFileReference`, group child, and Sources build phase.
- Start it **after the first frame** (it needs the view).

**Dart side:**

- A `ValueNotifier<DuoGeometry>` service parses the snapshot and drops malformed entries.
- Turn each *active* division with a width into
  `DisplayFeature(type: fold, state: postureHalfOpened)`, and merge it into `MediaQuery` above the app. Flutter's
  own dialogs, menus and `DisplayFeatureSubScreen` then avoid the fold, as they do on Android foldables.
- **Don't** pass the camera as a display feature. It would split the screen around a small cut-out, and dart:ui
  also asserts that a `cutout` must have state `unknown`.
- Decide the split: a vertical full-height fold means **book**, a horizontal full-width fold means **desk**.
  Hinges always split; folds only when `postureHalfOpened`. Then build two panes:
  - make the first pane end before `fold.left` / `fold.top` (minus your page padding);
  - add a spacer of the fold's size;
  - leave about 12 pt of extra gap so shadows and glows stay off the fold;
  - fall back to one column when a pane would be under about 200 pt.

### 4.4 Position the column from the system, not constants

- Pass `barLeft` / `barRight` to Dart and convert them to column coordinates (subtract `screenWidth − columnWidth`
  for a right column).
- Buttons start at `bar.top`; the tab pill ends at `bar.bottom`. Both are centred on `bar.center.x`, which is the
  camera's axis and sits ≈ 6 pt off the column centre.
- Centre-then-`Transform.translate(Offset(cx − width/2, 0))` works for any child width, and taps follow the
  move. `Align` / `CustomSingleChildLayout` either assume a child width or can't size from the child.
- Keep a fallback (we use 170 pt top, centred) for when the bridge isn't there.

---

## 5. Simulator workflow (most of the time went here)

1. **Runtime:**
   ```bash
   xcodebuild -downloadPlatform iOS -buildVersion 27.1
   ```
   About 7.85 GB, roughly 10 minutes. Xcode 27.1 is required.
2. **Device:**
   ```bash
   xcrun simctl create "Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1
   ```
   then `xcrun simctl boot <udid>`.
3. **The app is "Device Hub"** (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`), not Simulator.app.
   - Poses: the device window has toolbar buttons whose accessibility *help* text is **Closed**,
     **Partially Open** and **Open**.
   - Rotation: **Controls → Rotate Left / Rotate Right**. Orientation is under *Device → Orientation*.
   - There is **no `simctl` command for the hinge**.
   - Scriptable with AppleScript / System Events. Activate DeviceHub first, or menu clicks are silently ignored:
     ```applescript
     tell application "System Events" to tell process "DeviceHub"
       repeat with e in (entire contents of window 1)
         try
           if role of e is "AXButton" and help of e is "Partially Open" then click e
         end try
       end repeat
     end tell
     ```
   - Device Hub may open on a *real* paired phone. Select the simulator row in the sidebar first.
4. **Split view:** neither the app switcher nor Device Hub's menus offered a way to start it in the simulator. We
   validated the **left** column by holding the *closed* phone sideways instead: the column moves to the left
   there.
5. **arm64 only:**
   - iOS 26+ simulators on Apple Silicon refuse x86_64 / Rosetta builds ("needs to be updated by the
     developer… [iOS-simulator, x86_64]").
   - If a pod has no arm64-simulator slice, the usual `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` Podfile
     hack makes the app un-installable. Google **ML Kit** Face Detection is such a pod.
   - Workaround: a throwaway copy of the app with the pod replaced by a stub, building arm64 only
     (`EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` in both the Podfile and `ios/Flutter/Debug.xcconfig`).
6. **Xcode 27 `lipo -verify_arch` takes one arch only:** `lipo f -verify_arch arm64 x86_64` → "requires exactly
   one input file". Flutter 3.44's `debug_unpack_ios` uses the two-arch form and fails ("does not contain
   architectures arm64 x86_64"). Building one arch avoids it.
7. **Tap coordinates:** the simulator tool's taps use the display's **native portrait** coordinates. When the
   screen shows sideways, map (x, y) → (669 − y, x) for the open phone.
8. **Getting past sign-in without real credentials:** run the real app under
   `http.runWithClient(app.main, () => client)`.
   - The client answers your API host from fixtures (a `MockClient`) and passes other hosts (Google Fonts) to a
     real `http.Client()` made *outside* the zone.
   - Seed the session through the app's own save methods before calling `main`.
   - Launch with `flutter run -t lib/preview.dart`.
   - `kill -USR2 <pid from --pid-file>` hot-restarts a background `flutter run`.
9. **Probing:** `NSLog("PROBE …")` in the plugin, then read the values with:
   ```bash
   xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "PROBE"' --style compact
   ```

---

## 6. Checklist: "is my app iPhone Duo compatible?"

- [ ] Runs **sideways** on the inner display without broken layouts (portrait lock is ignored there).
- [ ] Closed: nothing under the camera or status. Content is laid out beside the vertical bar (or the vertical bar
      is disabled on purpose).
- [ ] Tabs at the bottom of the column; icon buttons at its top, from `edgeInsets(for: .bar…)`; text controls stay
      in content.
- [ ] Left column (split view / closed sideways) mirrors correctly, display features included.
- [ ] Open upright = normal phone layout (status top, tabs bottom).
- [ ] Book pose: two panes, nothing in the fold. Desk pose: controls in the bottom half.
- [ ] Folding or unfolding keeps navigation state (no tree-shape change).
- [ ] Full-screen pages and sheets cover the column's tabs as they would cover a bottom bar.
- [ ] Wide layouts follow size classes; an even column count when a fold exists.
- [ ] Dialogs off the fold (free in Flutter once `displayFeatures` is fed). Trailing anchor still to do.
- [ ] Tested on the 27.1 simulator in Closed, Open (both rotations) and Partially Open (both rotations).

## 7. Still open in the Omni HR implementation (worth doing in a new project from day one)

- Plain `AppBar` screens keep their back arrow in the bar; only the app's own `OmniAppBar` hands buttons to the
  column. A new app should route **every** app bar through one widget.
- The camera occlusion is reported but not used (e.g. to keep a camera preview clear of it).
- The Team overview still uses fixed 600 / 820 pt breakpoints and has no even-columns-with-fold logic.
- Dialog anchor points: Apple wants trailing; Flutter anchors top-left in LTR.
- Never tried: `preferredVerticalBarBehavior = .disabled`, `UIArrangementViewController`, scene accessories.
- Split view itself was never reached in the simulator (only the left column, via closed-sideways).
