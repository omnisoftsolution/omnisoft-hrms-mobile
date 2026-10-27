import 'dart:ui' show DisplayFeatureState, DisplayFeatureType, Rect;

import 'package:flutter/widgets.dart';

/// Which way an active fold cuts the screen.
///
/// - [vertical]: top to bottom — iPhone Duo held sideways and half-folded
///   like a book. Content and buttons go to the two sides.
/// - [horizontal]: side to side — iPhone Duo upright and half-folded on a
///   desk (laptop pose). Things to look at go on top, buttons on the
///   stable bottom half.
enum FoldAxis { vertical, horizontal }

/// An active fold that divides the screen, from
/// `MediaQuery.displayFeatures` (iOS through DuoFeatures, Android from
/// Flutter itself).
@immutable
class FoldSplit {
  const FoldSplit(this.axis, this.bounds);

  final FoldAxis axis;

  /// The fold in the MediaQuery's coordinates, margins included.
  final Rect bounds;

  @override
  bool operator ==(Object other) =>
      other is FoldSplit && other.axis == axis && other.bounds == bounds;

  @override
  int get hashCode => Object.hash(axis, bounds);
}

/// The fold that splits the screen in two right now, or null (flat, no
/// fold, or a feature that does not cross the whole screen). A hinge
/// (two separate panels) always splits; a fold only while half-open.
FoldSplit? foldSplitOf(MediaQueryData media) {
  final size = media.size;
  if (size.isEmpty) return null;
  for (final f in media.displayFeatures) {
    final splits =
        f.type == DisplayFeatureType.hinge ||
        (f.type == DisplayFeatureType.fold &&
            f.state == DisplayFeatureState.postureHalfOpened);
    if (!splits) continue;
    final b = f.bounds;
    const slack = 1.0;
    if (b.top <= slack &&
        b.bottom >= size.height - slack &&
        b.left > 0 &&
        b.right < size.width) {
      return FoldSplit(FoldAxis.vertical, b);
    }
    if (b.left <= slack &&
        b.right >= size.width - slack &&
        b.top > 0 &&
        b.bottom < size.height) {
      return FoldSplit(FoldAxis.horizontal, b);
    }
  }
  return null;
}
