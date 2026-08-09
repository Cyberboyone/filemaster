import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Splits [text] into pages that fit inside [width] x [height] using the
/// given [style], so long documents can be shown as numbered pages.
///
/// Pages break at whole lines (a line that is taller than a page gets its
/// own page). Joining all returned pages in order reproduces [text] exactly.
List<String> paginateText({
  required String text,
  required TextStyle style,
  required double width,
  required double height,
  TextDirection textDirection = TextDirection.ltr,
  double bottomInset = 24,
}) {
  if (text.trim().isEmpty) return [''];
  final usableHeight = math.max(height - bottomInset, 48.0);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    maxLines: null,
  )..layout(maxWidth: math.max(width, 40));

  final metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return [''];

  final lineStarts = <int>[];
  var runningTop = 0.0;
  for (final metric in metrics) {
    final y = runningTop.clamp(0.0, math.max(painter.height - 0.5, 0.0));
    final position = painter.getPositionForOffset(Offset(0, y + 0.5));
    lineStarts.add(painter.getLineBoundary(position).start);
    runningTop += metric.height;
  }

  final pages = <String>[];
  var lineIndex = 0;
  while (lineIndex < metrics.length) {
    var used = 0.0;
    var lineEnd = lineIndex;
    while (lineEnd < metrics.length &&
        used + metrics[lineEnd].height <= usableHeight) {
      used += metrics[lineEnd].height;
      lineEnd++;
    }
    if (lineEnd == lineIndex) lineEnd = lineIndex + 1;

    final pageStart = lineStarts[lineIndex];
    final pageEnd = lineEnd < metrics.length ? lineStarts[lineEnd] : text.length;
    if (pageEnd > pageStart) {
      pages.add(text.substring(pageStart, pageEnd));
    }
    lineIndex = lineEnd;
  }
  return pages.isEmpty ? [''] : pages;
}