import 'package:flutter/material.dart';

import '../utils/doc_format.dart';

/// Functional file-type color coding (PDF orange, Word blue, Excel green,
/// images purple, ...) used for file icons, badges and chips.
abstract final class FormatColors {
  static const Color pdf = Color(0xFFEA580C);
  static const Color word = Color(0xFF2563EB);
  static const Color excel = Color(0xFF16A34A);
  static const Color powerpoint = Color(0xFFE11D48);
  static const Color text = Color(0xFF475569);
  static const Color image = Color(0xFF9333EA);
  static const Color archive = Color(0xFFB45309);
  static const Color other = Color(0xFF64748B);

  static Color of(DocFormat format) {
    return switch (format) {
      DocFormat.pdf => pdf,
      DocFormat.word => word,
      DocFormat.excel => excel,
      DocFormat.powerpoint => powerpoint,
      DocFormat.text => text,
      DocFormat.image => image,
      DocFormat.archive => archive,
      DocFormat.other => other,
    };
  }

  /// Icon/glyph color that keeps enough contrast on the given brightness.
  static Color glyph(Color color, Brightness brightness) {
    if (brightness == Brightness.dark) {
      return Color.lerp(color, Colors.white, 0.35)!;
    }
    return color;
  }

  /// Soft tinted background for the format color.
  static Color container(Color color, Brightness brightness) {
    final alpha = brightness == Brightness.dark ? 0.26 : 0.12;
    return color.withValues(alpha: alpha);
  }
}
