import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/duo_fold.dart';

MediaQueryData _media(Size size, List<DisplayFeature> features) =>
    MediaQueryData(size: size, displayFeatures: features);

DisplayFeature _fold(
  Rect r, {
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
  DisplayFeatureType type = DisplayFeatureType.fold,
}) => DisplayFeature(bounds: r, type: type, state: state);

void main() {
  test('no features: no split', () {
    expect(foldSplitOf(_media(const Size(951, 669), const [])), isNull);
  });

  test('half-folded like a book: a top-to-bottom fold splits vertically', () {
    const r = Rect.fromLTWH(455, 0, 41, 669);
    expect(
      foldSplitOf(_media(const Size(951, 669), [_fold(r)])),
      const FoldSplit(FoldAxis.vertical, r),
    );
  });

  test('half-folded on a desk: a side-to-side fold splits horizontally', () {
    const r = Rect.fromLTWH(0, 455, 669, 41);
    expect(
      foldSplitOf(_media(const Size(669, 951), [_fold(r)])),
      const FoldSplit(FoldAxis.horizontal, r),
    );
  });

  test('a flat fold (not half-open) does not split', () {
    const r = Rect.fromLTWH(455, 0, 41, 669);
    expect(
      foldSplitOf(
        _media(const Size(951, 669), [
          _fold(r, state: DisplayFeatureState.postureFlat),
        ]),
      ),
      isNull,
    );
  });

  test('a hinge between two panels always splits', () {
    const r = Rect.fromLTWH(455, 0, 41, 669);
    expect(
      foldSplitOf(
        _media(const Size(951, 669), [
          _fold(
            r,
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.unknown,
          ),
        ]),
      )?.axis,
      FoldAxis.vertical,
    );
  });

  test('a small cut-out (camera) does not split', () {
    expect(
      foldSplitOf(
        _media(const Size(951, 669), [
          _fold(
            const Rect.fromLTWH(700, 10, 30, 30),
            type: DisplayFeatureType.cutout,
            // dart:ui allows only `unknown` for a cut-out.
            state: DisplayFeatureState.unknown,
          ),
        ]),
      ),
      isNull,
    );
  });
}
