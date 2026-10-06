import 'package:flutter/material.dart';

/// One semantic colour of My day (spec 2026-10-06 §4.1): the tile fill
/// (white text on it), the tint for chips and cells, the text on that
/// tint, and the dot / rail colour.
class MyDayTone {
  final Color fill;
  final Color tint;
  final Color onTint;
  final Color dot;

  const MyDayTone({
    required this.fill,
    required this.tint,
    required this.onTint,
    required this.dot,
  });
}

class MyDayColors {
  MyDayColors._();

  static const work = MyDayTone(
    fill: Color(0xFF006971), tint: Color(0xFFDCEFF1),
    onTint: Color(0xFF004F55), dot: Color(0xFF006971));
  static const brk = MyDayTone(
    fill: Color(0xFF1D477E), tint: Color(0xFFD6E3FF),
    onTint: Color(0xFF1D477E), dot: Color(0xFF395F97));
  static const leave = MyDayTone(
    fill: Color(0xFF395F97), tint: Color(0xFFD6E3FF),
    onTint: Color(0xFF1D477E), dot: Color(0xFF395F97));
  static const late = MyDayTone(
    fill: Color(0xFF8A5A00), tint: Color(0xFFFFE4A8),
    onTint: Color(0xFF6B4400), dot: Color(0xFFD99A1C));
  static const overtime = MyDayTone(
    fill: Color(0xFF1B5E38), tint: Color(0xFFDDF3E4),
    onTint: Color(0xFF1B5E38), dot: Color(0xFF2E8B57));
  static const missing = MyDayTone(
    fill: Color(0xFF93000A), tint: Color(0xFFFFDAD6),
    onTint: Color(0xFF93000A), dot: Color(0xFFBA1A1A));
  static const waiting = MyDayTone(
    fill: Color(0xFF516161), tint: Color(0xFFECEEF0),
    onTint: Color(0xFF55666A), dot: Color(0xFFBCC9CA));
  static const holiday = MyDayTone(
    fill: Color(0xFF3A4A49), tint: Color(0xFFE0E3E5),
    onTint: Color(0xFF3D494A), dot: Color(0xFF3D494A));
}
