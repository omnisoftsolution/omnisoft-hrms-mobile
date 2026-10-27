import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The hinge as UIKit reports it (`UIHinge.Status`); [none] = no hinge
/// (not an iPhone Duo, not iOS 27.1, or not started).
enum DuoHinge { none, unknown, closed, partiallyOpen, fullyOpen }

/// One UIKit reserved region (`UIView.ReservedRegion`), in Flutter
/// logical pixels of the whole view, margins included.
@immutable
class DuoRegion {
  const DuoRegion(this.rect, {required this.active});

  final Rect rect;
  final bool active;

  @override
  bool operator ==(Object other) =>
      other is DuoRegion && other.rect == rect && other.active == active;

  @override
  int get hashCode => Object.hash(rect, active);
}

/// What `ios/Runner/DuoPlugin.swift` reports: the fold ([divisions]), the
/// inner FaceTime camera ([occlusions]), the hinge and where iOS puts a
/// vertical bar on either edge ([barLeft], [barRight]).
@immutable
class DuoGeometry {
  const DuoGeometry({
    this.hinge = DuoHinge.none,
    this.divisions = const [],
    this.occlusions = const [],
    this.barLeft,
    this.barRight,
  });

  static const none = DuoGeometry();

  /// The channel's snapshot; anything malformed reads as [none].
  factory DuoGeometry.fromMap(Map<Object?, Object?> map) {
    if (map['available'] != true) return none;
    return DuoGeometry(
      hinge: DuoHinge.values.firstWhere(
        (h) => h.name == map['hinge'],
        orElse: () => DuoHinge.none,
      ),
      divisions: _regions(map['divisions']),
      occlusions: _regions(map['occlusions']),
      barLeft: _rect(map['barLeft']),
      barRight: _rect(map['barRight']),
    );
  }

  final DuoHinge hinge;
  final List<DuoRegion> divisions;
  final List<DuoRegion> occlusions;

  /// Where iOS places a 48 pt vertical bar on the left / right edge
  /// (`edgeInsets(for: .bar(onEdge:extent:))`): below the clock, status
  /// icons and camera, centred on the camera, above the home indicator.
  /// Closed: right = (394, 170, 48, 474) in a 466 × 678 view.
  final Rect? barLeft;
  final Rect? barRight;

  /// The screen has a fold at all, folded or flat (Apple: prefer an even
  /// number of columns then, whatever the fold's state).
  bool get hasFold => divisions.isNotEmpty;

  /// The fold while the phone is half-folded (UIKit only activates the
  /// division region then; flat it is inactive with zero width).
  Iterable<DuoRegion> get activeDivisions =>
      divisions.where((r) => r.active && r.rect.shortestSide > 0);

  /// The active fold as Flutter display features, so `showDialog`,
  /// menus and `DisplayFeatureSubScreen` keep clear of it as they do on
  /// Android foldables. The camera is left out on purpose: as a display
  /// feature it would split the screen around a small cut-out.
  List<DisplayFeature> get displayFeatures => [
    for (final r in activeDivisions)
      DisplayFeature(
        bounds: r.rect,
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      ),
  ];

  static Rect? _rect(Object? raw) {
    if (raw is! List || raw.length < 4) return null;
    final n = [for (final v in raw.take(4)) v is num ? v.toDouble() : null];
    if (n.contains(null) || n[2]! <= 0 || n[3]! <= 0) return null;
    return Rect.fromLTWH(n[0]!, n[1]!, n[2]!, n[3]!);
  }

  static List<DuoRegion> _regions(Object? raw) {
    if (raw is! List) return const [];
    final out = <DuoRegion>[];
    for (final item in raw) {
      if (item is! List || item.length < 5) continue;
      final n = [for (final v in item.take(5)) v is num ? v.toDouble() : null];
      if (n.contains(null)) continue;
      out.add(
        DuoRegion(
          Rect.fromLTWH(n[0]!, n[1]!, n[2]!, n[3]!),
          active: n[4]! != 0,
        ),
      );
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is DuoGeometry &&
      other.hinge == hinge &&
      listEquals(other.divisions, divisions) &&
      listEquals(other.occlusions, occlusions) &&
      other.barLeft == barLeft &&
      other.barRight == barRight;

  @override
  int get hashCode => Object.hash(
    hinge,
    Object.hashAll(divisions),
    Object.hashAll(occlusions),
    barLeft,
    barRight,
  );
}

/// iPhone Duo geometry over the 'omnihr/duo' channel. Flutter fills
/// `MediaQuery.displayFeatures` only on Android; on iOS the fold is
/// invisible to Dart without this. iOS only; elsewhere it stays [none].
class DuoService extends ValueNotifier<DuoGeometry> {
  DuoService._() : super(DuoGeometry.none);

  static final DuoService instance = DuoService._();

  static const MethodChannel _channel = MethodChannel('omnihr/duo');

  bool _started = false;

  /// Starts the native observer once (after the first frame: it needs the
  /// Flutter view). Failures leave [DuoGeometry.none].
  Future<void> start() async {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && call.arguments is Map) {
        value = DuoGeometry.fromMap(call.arguments as Map);
      }
    });
    await _read('start');
  }

  /// Re-reads the geometry (the camera region has no change callback).
  Future<void> refresh() => _started ? _read('get') : Future.value();

  Future<void> _read(String method) async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(method);
      if (map != null) value = DuoGeometry.fromMap(map);
    } on PlatformException catch (e) {
      debugPrint('omnihr/duo $method failed: ${e.code}');
    } on MissingPluginException {
      // An older native build: no Duo support, nothing to do.
    }
  }

  @visibleForTesting
  set debugGeometry(DuoGeometry g) => value = g;
}

/// Adds the iPhone Duo fold to `MediaQuery.displayFeatures` for
/// everything below (sits outside `SideColumnHost`, so the bounds are in
/// whole-view coordinates), and hands the whole [DuoGeometry] down
/// ([geometryOf]).
class DuoFeatures extends StatelessWidget {
  const DuoFeatures({super.key, required this.child, this.service});

  final Widget child;

  /// Test seam; defaults to [DuoService.instance].
  final DuoService? service;

  /// The geometry above [context]; [DuoGeometry.none] without a
  /// [DuoFeatures].
  static DuoGeometry geometryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DuoScope>()?.geometry ??
      DuoGeometry.none;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DuoGeometry>(
      valueListenable: service ?? DuoService.instance,
      child: child,
      builder: (context, geometry, child) {
        // Same tree shape folded or not: a fold appearing must not rebuild
        // the app (its Navigator, pushed pages and state).
        final extra = geometry.displayFeatures;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: extra.isEmpty
              ? media
              : media.copyWith(
                  displayFeatures: [...media.displayFeatures, ...extra],
                ),
          child: _DuoScope(geometry: geometry, child: child!),
        );
      },
    );
  }
}

class _DuoScope extends InheritedWidget {
  const _DuoScope({required this.geometry, required super.child});

  final DuoGeometry geometry;

  @override
  bool updateShouldNotify(_DuoScope old) => old.geometry != geometry;
}
