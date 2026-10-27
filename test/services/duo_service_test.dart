import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/duo_service.dart';

const _channel = MethodChannel('omnihr/duo');

Map<String, Object?> _snap({
  bool available = true,
  String hinge = 'partiallyOpen',
  List<List<num>> divisions = const [],
  List<List<num>> occlusions = const [],
}) => {
  'available': available,
  'hinge': hinge,
  'angle': 1.9,
  'divisions': divisions,
  'occlusions': occlusions,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DuoGeometry.fromMap', () {
    test('not available (older iOS / not a Duo) reads as none', () {
      expect(
        DuoGeometry.fromMap(
          _snap(
            available: false,
            divisions: [
              [455, 0, 41, 669, 1],
            ],
          ),
        ),
        DuoGeometry.none,
      );
    });

    test('reads the hinge, the fold and the camera', () {
      final g = DuoGeometry.fromMap(
        _snap(
          divisions: [
            [455, 0, 41, 669, 1],
          ],
          occlusions: [
            [700, 12, 40, 40, 0],
          ],
        ),
      );
      expect(g.hinge, DuoHinge.partiallyOpen);
      expect(g.divisions, [
        const DuoRegion(Rect.fromLTWH(455, 0, 41, 669), active: true),
      ]);
      expect(g.occlusions.single.active, isFalse);
      expect(g.hasFold, isTrue);
    });

    test('malformed regions and an unknown hinge are dropped', () {
      final g = DuoGeometry.fromMap({
        'available': true,
        'hinge': 'sideways',
        'divisions': [
          [1, 2, 3],
          ['a', 0, 1, 1, 1],
          'x',
        ],
        'occlusions': 'nope',
      });
      expect(g.hinge, DuoHinge.none);
      expect(g.divisions, isEmpty);
      expect(g.occlusions, isEmpty);
    });
  });

  group('displayFeatures', () {
    test('only an active fold with a width becomes a half-opened fold', () {
      final g = DuoGeometry.fromMap(
        _snap(
          divisions: [
            [475, 0, 0, 669, 0], // flat: inactive, zero width
          ],
        ),
      );
      expect(g.hasFold, isTrue);
      expect(g.displayFeatures, isEmpty);

      final folded = DuoGeometry.fromMap(
        _snap(
          divisions: [
            [455, 0, 41, 669, 1],
          ],
          occlusions: [
            [700, 12, 40, 40, 1],
          ],
        ),
      );
      final f = folded.displayFeatures.single;
      expect(f.type, DisplayFeatureType.fold);
      expect(f.state, DisplayFeatureState.postureHalfOpened);
      expect(f.bounds, const Rect.fromLTWH(455, 0, 41, 669));
    });
  });

  testWidgets('DuoFeatures adds the fold to MediaQuery.displayFeatures', (
    tester,
  ) async {
    final service = DuoService.instance;
    addTearDown(() => service.debugGeometry = DuoGeometry.none);
    late List<DisplayFeature> seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(951, 669)),
        child: DuoFeatures(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context).displayFeatures;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen, isEmpty);
    service.debugGeometry = DuoGeometry.fromMap(
      _snap(
        divisions: [
          [455, 0, 41, 669, 1],
        ],
      ),
    );
    await tester.pump();
    expect(seen.single.bounds, const Rect.fromLTWH(455, 0, 41, 669));
  });

  test('start on iOS reads the snapshot and follows "changed"', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      return _snap(hinge: 'fullyOpen');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    final service = DuoService.instance;
    addTearDown(() => service.debugGeometry = DuoGeometry.none);
    await service.start();
    await service.start(); // once only
    expect(calls, ['start']);
    expect(service.value.hinge, DuoHinge.fullyOpen);

    // Native → Dart: the phone was half-folded.
    await messenger.handlePlatformMessage(
      'omnihr/duo',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(
          'changed',
          _snap(
            divisions: [
              [455, 0, 41, 669, 1],
            ],
          ),
        ),
      ),
      (_) {},
    );
    expect(service.value.activeDivisions, hasLength(1));

    await service.refresh();
    expect(calls, ['start', 'get']);
  });
}
