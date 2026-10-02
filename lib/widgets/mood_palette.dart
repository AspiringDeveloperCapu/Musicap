import 'package:flutter/material.dart';

/// Deterministic gradient palette for genre/mood surfaces.
///
/// Genre items carry no artwork, so tiles and hero headers derive their
/// colors from the item title. The palette is curated to stay vibrant on
/// both light and dark themes and white text remains readable on all pairs.
class MoodPalette {
  MoodPalette._();

  static const List<List<Color>> _pairs = [
    [Color(0xFF7C4DFF), Color(0xFFB388FF)],
    [Color(0xFFE91E63), Color(0xFFFF8A80)],
    [Color(0xFFFF6D00), Color(0xFFFFD180)],
    [Color(0xFF00BFA5), Color(0xFF64FFDA)],
    [Color(0xFF2979FF), Color(0xFF82B1FF)],
    [Color(0xFF00C853), Color(0xFFB9F6CA)],
    [Color(0xFFD50000), Color(0xFFFF8A80)],
    [Color(0xFF00B0FF), Color(0xFF80D8FF)],
    [Color(0xFFFFAB00), Color(0xFFFFE57F)],
    [Color(0xFFD500F9), Color(0xFFEA80FC)],
    [Color(0xFF1DE9B6), Color(0xFFA7FFEB)],
    [Color(0xFF3D5AFE), Color(0xFF8C9EFF)],
    [Color(0xFFFF4081), Color(0xFFFF80AB)],
    [Color(0xFF76FF03), Color(0xFFCCFF90)],
    [Color(0xFF6200EA), Color(0xFFB388FF)],
    [Color(0xFF18FFFF), Color(0xFF84FFFF)],
  ];

  /// Stable hash so the same title always gets the same colors.
  static int _hash(String title) {
    var h = 0;
    for (final code in title.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }

  /// The gradient pair for [title].
  static List<Color> colors(String title) => _pairs[_hash(title) % _pairs.length];

  /// A linear gradient (top-left → bottom-right) for [title].
  static LinearGradient gradient(String title) {
    final pair = colors(title);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: pair,
    );
  }

  /// The lead color for [title] — used for chips and solid accents that
  /// should visually match the full gradient.
  static Color primary(String title) => colors(title).first;
}
