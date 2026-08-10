import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:xml/xml.dart';

/// Renders PowerPoint (.pptx) slides close to the original: slide
/// background, positioned shapes (rectangle fills, text boxes, images) and
/// run-level text styling (size, bold, italic, underline, color) with
/// alignment. Geometry comes straight from the OOXML drawing markup using
/// EMU units; text line metrics use 96 dpi so 72 dpi * (96/72) = 96.
///
/// The API is intentionally small:
/// - [parsePptxRender] turns the raw bytes into [PptxRenderSlide]s.
/// - [PptxSlidePainter] draws a slide onto a canvas at a given scale.
/// - [PptxSlideView] wraps the painter in an aspect-correct widget.

class PptxTextLine {
  const PptxTextLine({
    required this.text,
    this.sizePt = 18,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
    this.align = 'l',
    this.leftInsetEmu = 0,
    this.topInsetEmu = 0,
  });

  final String text;
  final double sizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final Color? color;

  /// 'l' | 'ctr' | 'r' | 'just' | 'dist' (bodyPr/paragraph pPr algn).
  final String align;

  /// Text inset (a:bodyPr lIns/tIns) in EMU, applied as padding.
  final double leftInsetEmu;
  final double topInsetEmu;
}

class PptxShape {
  const PptxShape({
    required this.xEmu,
    required this.yEmu,
    required this.widthEmu,
    required this.heightEmu,
    this.fillColor,
    this.imageBytes,
    this.lines = const [],
  });

  final double xEmu;
  final double yEmu;
  final double widthEmu;
  final double heightEmu;

  /// Solid fill colour (a:solidFill/a:srgbClr) if the shape has one.
  final Color? fillColor;

  /// Raw image bytes resolved through the slide rels (ppt/media/...).
  final Uint8List? imageBytes;

  final List<PptxTextLine> lines;

  bool get hasContent =>
      lines.isNotEmpty || imageBytes != null || fillColor != null;
}

class PptxRenderSlide {
  const PptxRenderSlide({
    required this.index,
    required this.widthEmu,
    required this.heightEmu,
    this.backgroundColor,
    this.backgroundImageBytes,
    this.shapes = const [],
  });

  final int index;

  /// Slide size from `p:sldSz` (EMU). Default 12192000 x 6858000.
  final double widthEmu;
  final double heightEmu;

  final Color? backgroundColor;

  /// Full-bleed background image from a layout/master (rare).
  final Uint8List? backgroundImageBytes;

  final List<PptxShape> shapes;

  bool get hasContent =>
      shapes.any((shape) => shape.hasContent) || backgroundImageBytes != null;
}

/// Parses a .pptx archive into renderable slides, resolving text, fills,
/// images and geometry. Throws `FormatException` if `bytes` is not a
/// readable PowerPoint archive.
List<PptxRenderSlide> parsePptxRender(Uint8List bytes) {
  Archive? archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Not a PPTX archive');
  }
  if (archive == null || archive.isEmpty) {
    throw const FormatException('Not a PPTX archive');
  }

  final count = _presentationCount(archive);
  final slides = <PptxRenderSlide>[];
  for (var i = 0; i < count; i++) {
    final slidesXml = _readEntry(archive, 'ppt/slides/slide$i.xml');
    if (slidesXml == null) continue;
    final document = XmlDocument.parse(
      utf8.decode(slidesXml, allowMalformed: true),
    );
    final slide = _parseSlide(document, archive, i);
    slides.add(slide);
  }
  return slides;
}

// --- parsing helpers -------------------------------------------------------

int _presentationCount(Archive archive) {
  final presXml = _readEntry(archive, 'ppt/presentation.xml');
  if (presXml != null) {
    try {
      final document = XmlDocument.parse(
        utf8.decode(presXml, allowMalformed: true),
      );
      final xml = document.rootElement;
      final sldIdLst = _childByLocal(xml, 'sldIdLst');
      if (sldIdLst != null) {
        return sldIdLst.childElements
            .where((e) => e.name.local == 'sldId')
            .length;
      }
    } catch (_) {}
  }
  return 0;
}

PptxRenderSlide _parseSlide(XmlDocument document, Archive archive, int index) {
  final xml = document.rootElement;
  double widthEmu = 12192000;
  double heightEmu = 6858000;
  Color? backgroundColor;
  Uint8List? backgroundImageBytes;

  final sldSz = _childByLocal(xml, 'sldSz');
  if (sldSz != null) {
    final w = _attr(sldSz, 'cx');
    final h = _attr(sldSz, 'cy');
    if (w != null) widthEmu = double.tryParse(w) ?? widthEmu;
    if (h != null) heightEmu = double.tryParse(h) ?? heightEmu;
  }

  final bg = _descendantsByLocal(xml, 'bg').firstOrNull;
  if (bg != null) {
    final bgRef = _childByLocal(bg, 'bgRef');
    if (bgRef != null) {
      backgroundColor = _shapeColor(bgRef);
    }
    final blipFill = _childByLocal(bg, 'blipFill');
    if (blipFill != null) {
      final blip = _descendantsByLocal(blipFill, 'blip').firstOrNull;
      if (blip != null) {
        final rid = _attr(blip, 'r:embed');
        backgroundImageBytes = _resolveImage(rid, index, archive);
      }
    }
  }

  final spTree = _descendantsByLocal(xml, 'spTree').firstOrNull;
  final shapes = <PptxShape>[];
  if (spTree != null) {
    for (final element in spTree.childElements) {
      final local = element.name.local;
      if (local == 'sp' || local == 'pic') {
        final shape = _parseShape(element, index, archive);
        if (shape != null) shapes.add(shape);
      } else if (local == 'grpSp') {
        shapes.addAll(_parseGroup(element, index, archive));
      }
    }
  }

  return PptxRenderSlide(
    index: index,
    widthEmu: widthEmu,
    heightEmu: heightEmu,
    backgroundColor: backgroundColor,
    backgroundImageBytes: backgroundImageBytes,
    shapes: shapes,
  );
}

/// Walks a group shape (grpSp) and returns the shapes it contains.
List<PptxShape> _parseGroup(XmlElement group, int slideIndex, Archive archive) {
  final shapes = <PptxShape>[];
  final groupXfrm = _shapeXfrm(group);
  final gOff = groupXfrm != null ? _childByLocal(groupXfrm, 'off') : null;
  final gChOff = groupXfrm != null ? _childByLocal(groupXfrm, 'chOff') : null;
  if (gOff == null || gChOff == null) return shapes;

  final gx = double.tryParse(_attr(gOff, 'x') ?? '') ?? 0;
  final gy = double.tryParse(_attr(gOff, 'y') ?? '') ?? 0;
  final chx = double.tryParse(_attr(gChOff, 'x') ?? '') ?? 0;
  final chy = double.tryParse(_attr(gChOff, 'y') ?? '') ?? 0;

  for (final element in group.childElements) {
    final local = element.name.local;
    if (local == 'sp' || local == 'pic') {
      final shape = _parseShape(element, slideIndex, archive);
      if (shape == null) continue;
      final xfrm = _shapeXfrm(element);
      final off = xfrm != null ? _childByLocal(xfrm, 'off') : null;
      final ext = xfrm != null ? _childByLocal(xfrm, 'ext') : null;
      if (off != null) {
        final x = double.tryParse(_attr(off, 'x') ?? '') ?? shape.xEmu;
        final y = double.tryParse(_attr(off, 'y') ?? '') ?? shape.yEmu;
        final w =
            double.tryParse(ext != null ? _attr(ext, 'cx') ?? '' : '') ??
            shape.widthEmu;
        final h =
            double.tryParse(ext != null ? _attr(ext, 'cy') ?? '' : '') ??
            shape.heightEmu;
        shapes.add(
          PptxShape(
            xEmu: gx + (x - chx),
            yEmu: gy + (y - chy),
            widthEmu: w,
            heightEmu: h,
            fillColor: shape.fillColor,
            imageBytes: shape.imageBytes,
            lines: shape.lines,
          ),
        );
      } else {
        shapes.add(shape);
      }
    } else if (local == 'grpSp') {
      shapes.addAll(_parseGroup(element, slideIndex, archive));
    }
  }
  return shapes;
}

PptxShape? _parseShape(XmlElement element, int slideIndex, Archive archive) {
  final xfrm = _shapeXfrm(element);
  final off = xfrm != null ? _childByLocal(xfrm, 'off') : null;
  final ext = xfrm != null ? _childByLocal(xfrm, 'ext') : null;
  if (off == null || ext == null) return null;

  final x = double.tryParse(_attr(off, 'x') ?? '') ?? 0;
  final y = double.tryParse(_attr(off, 'y') ?? '') ?? 0;
  final w = double.tryParse(_attr(ext, 'cx') ?? '') ?? 0;
  final h = double.tryParse(_attr(ext, 'cy') ?? '') ?? 0;

  var fillColor = _shapeFill(element);

  Uint8List? imageBytes;
  final blipFill = _childByLocal(element, 'blipFill');
  if (blipFill != null && element.name.local == 'pic') {
    final blip = _descendantsByLocal(blipFill, 'blip').firstOrNull;
    if (blip != null) {
      final rid = _attr(blip, 'r:embed');
      imageBytes = _resolveImage(rid, slideIndex, archive);
      if (imageBytes == null) fillColor = null;
    }
  }

  final lines = _parseTextBody(element);

  // Skip invisible placeholder shells (no text, no fill, no image).
  if (lines.isEmpty && imageBytes == null && fillColor == null) {
    return null;
  }

  return PptxShape(
    xEmu: x,
    yEmu: y,
    widthEmu: w,
    heightEmu: h,
    fillColor: fillColor,
    imageBytes: imageBytes,
    lines: lines,
  );
}

List<PptxTextLine> _parseTextBody(XmlElement element) {
  final txBody = _childByLocal(element, 'txBody');
  if (txBody == null) return const <PptxTextLine>[];

  final bodyPr = _childByLocal(txBody, 'bodyPr');
  double leftInset = 0;
  double topInset = 0;
  if (bodyPr != null) {
    leftInset = double.tryParse(_attr(bodyPr, 'lIns') ?? '') ?? 0;
    topInset = double.tryParse(_attr(bodyPr, 'tIns') ?? '') ?? 0;
  }

  final lines = <PptxTextLine>[];

  double? paragraphSizePt;
  String paragraphAlign = 'l';
  for (final para in txBody.childElements) {
    if (para.name.local != 'p') continue;
    final pPr = _childByLocal(para, 'pPr');
    if (pPr != null) {
      final sz = _attr(pPr, 'sz');
      if (sz != null) paragraphSizePt = (double.tryParse(sz) ?? 0) / 100;
      paragraphAlign = _attr(pPr, 'algn') ?? paragraphAlign;
    }

    final buffer = StringBuffer();
    final style = <String, Object?>{
      'sz': paragraphSizePt,
      'b': false,
      'i': false,
      'u': false,
      'color': null,
      'align': paragraphAlign,
    };
    var hasText = false;

    for (final child in para.childElements) {
      if (child.name.local == 'r') {
        final rPr = _childByLocal(child, 'rPr');
        if (rPr != null) {
          final sz = _attr(rPr, 'sz');
          if (sz != null) style['sz'] = (double.tryParse(sz) ?? 0) / 100;
          final b = _attr(rPr, 'b');
          if (b == '1' || b == 'true') style['b'] = true;
          final i = _attr(rPr, 'i');
          if (i == '1' || i == 'true') style['i'] = true;
          final u = _attr(rPr, 'u');
          if (u != null && u != 'none') style['u'] = true;
          final srgb = _descendantsByLocal(rPr, 'srgbClr').firstOrNull;
          if (srgb != null) {
            final val = _attr(srgb, 'val');
            if (val != null) style['color'] = _parseHexColor(val);
          }
        }
        final t = _childByLocal(child, 't');
        if (t != null && t.innerText.isNotEmpty) {
          buffer.write(t.innerText);
          hasText = true;
        }
      } else if (child.name.local == 'br') {
        buffer.write('\n');
        hasText = true;
      } else if (child.name.local == 'fld') {
        final t = _descendantsByLocal(child, 't').firstOrNull;
        if (t != null && t.innerText.isNotEmpty) {
          buffer.write(t.innerText);
          hasText = true;
        }
      }
    }

    if (!hasText) continue;
    final text = buffer.toString().trim();
    if (text.isEmpty) continue;
    lines.add(
      PptxTextLine(
        text: text,
        sizePt: (style['sz'] as double?) ?? 18,
        bold: style['b'] as bool,
        italic: style['i'] as bool,
        underline: style['u'] as bool,
        color: style['color'] as Color?,
        align: style['align'] as String,
        leftInsetEmu: leftInset,
        topInsetEmu: topInset,
      ),
    );
  }
  return lines;
}

Color? _shapeFill(XmlElement element) {
  final solidFill = _descendantsByLocal(element, 'solidFill').firstOrNull;
  if (solidFill != null) {
    final srgb = _descendantsByLocal(solidFill, 'srgbClr').firstOrNull;
    if (srgb != null) {
      final val = _attr(srgb, 'val');
      if (val != null) return _parseHexColor(val);
    }
  }
  final gradFill = _descendantsByLocal(element, 'gradFill').firstOrNull;
  if (gradFill != null) {
    final colorLst = _childByLocal(gradFill, 'gsLst');
    if (colorLst != null) {
      final stops = colorLst.childElements
          .where((e) => e.name.local == 'gs')
          .toList();
      if (stops.isNotEmpty) {
        final stop = stops.firstWhere(
          (e) => _descendantsByLocal(e, 'srgbClr').isNotEmpty,
          orElse: () => stops.first,
        );
        final srgb = _descendantsByLocal(stop, 'srgbClr').firstOrNull;
        if (srgb != null) {
          final val = _attr(srgb, 'val');
          if (val != null) return _parseHexColor(val);
        }
      }
    }
  }
  return null;
}

Color? _shapeColor(XmlElement element) {
  final srgb = _descendantsByLocal(element, 'srgbClr').firstOrNull;
  if (srgb != null && _hasAncestor(srgb, 'solidFill')) {
    final val = _attr(srgb, 'val');
    if (val != null) return _parseHexColor(val);
  }
  return null;
}

Uint8List? _resolveImage(String? rid, int slideIndex, Archive archive) {
  if (rid == null) return null;
  final rels = _readEntry(
    archive,
    'ppt/slides/_rels/slide$slideIndex.xml.rels',
  );
  if (rels == null) return null;
  try {
    final document = XmlDocument.parse(utf8.decode(rels, allowMalformed: true));
    for (final relationship in document.rootElement.childElements) {
      if (relationship.name.local != 'Relationship') continue;
      if (_attr(relationship, 'Id') != rid) continue;
      final target = _attr(relationship, 'Target');
      if (target == null) return null;
      final targetMode = _attr(relationship, 'TargetMode');
      if (targetMode == 'External') return null;
      final mediaPath = _normalizeTarget('ppt/slides', target);
      return _readEntryBytes(archive, mediaPath);
    }
  } catch (_) {
    return null;
  }
  return null;
}

List<int>? _readEntry(Archive archive, String name) {
  for (final entry in archive.files) {
    if (entry.name == name) return entry.content as List<int>?;
  }
  return null;
}

/// Version of [_readEntry] that returns an immutable byte buffer.
Uint8List? _readEntryBytes(Archive archive, String name) {
  final entry = _readEntry(archive, name);
  return entry == null ? null : Uint8List.fromList(entry);
}

/// Resolves an OOXML relationship target (relative or absolute) to an
/// archive entry name, collapsing `..` segments.
String _normalizeTarget(String baseDir, String target) {
  final path = target.replaceAll('\\', '/').replaceAll('%20', ' ');
  if (path.startsWith('/')) return path.substring(1);
  final segments = (baseDir + '/' + Uri.decodeComponent(path)).split('/');
  final resolved = <String>[];
  for (final segment in segments) {
    if (segment == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
    } else if (segment.isNotEmpty && segment != '.') {
      resolved.add(segment);
    }
  }
  return resolved.join('/');
}

// --- painter ---------------------------------------------------------------

/// Custom painter that draws one slide. [scale] converts EMU to logical px.
class PptxSlidePainter extends CustomPainter {
  PptxSlidePainter({
    required this.slide,
    required this.scale,
    this.images = const {},
  });

  final PptxRenderSlide slide;
  final double scale;

  /// Decoded images: key -1 is the slide background, 0..n are the shapes.
  final Map<int, ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.fill
        ..color = slide.backgroundColor ?? const Color(0xFFFFFFFF),
    );
    final bkgImage = images[-1];
    if (bkgImage != null) {
      _paintImage(canvas, bkgImage, Offset.zero & size, BoxFit.contain);
    }

    for (var i = 0; i < slide.shapes.length; i++) {
      final shape = slide.shapes[i];
      final rect = Rect.fromLTWH(
        shape.xEmu * scale,
        shape.yEmu * scale,
        shape.widthEmu * scale,
        shape.heightEmu * scale,
      );
      final fill = shape.fillColor;
      if (fill != null) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = fill,
        );
      }
      final shapeImage = images[i];
      if (shapeImage != null) {
        _paintImage(canvas, shapeImage, rect, BoxFit.fill);
      }
      if (shape.lines.isEmpty) continue;
      canvas.save();
      canvas.clipRect(rect);
      final leftInset = shape.lines.first.leftInsetEmu * scale;
      final topInset = shape.lines.first.topInsetEmu * scale;
      final textArea = Rect.fromLTWH(
        rect.left + leftInset,
        rect.top + topInset,
        (rect.width - leftInset * 2).clamp(10, double.infinity),
        rect.height - topInset,
      );
      var py = textArea.top;
      for (final line in shape.lines) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: line.text,
            style: TextStyle(
              fontSize: line.sizePt * 96 / 72 * scale,
              fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
              fontStyle: line.italic ? FontStyle.italic : FontStyle.normal,
              decoration: line.underline ? TextDecoration.underline : null,
              color: line.color ?? const Color(0xFF000000),
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: textArea.width);
        var dx = textArea.left;
        switch (line.align) {
          case 'ctr':
            dx = textArea.left + (textArea.width - textPainter.width) / 2;
          case 'r':
            dx = textArea.right - textPainter.width;
          case 'just':
          case 'dist':
            dx = textArea.left;
        }
        textPainter.paint(canvas, Offset(dx, py));
        py += textPainter.height + 2 * scale;
      }
      canvas.restore();
    }
  }

  void _paintImage(Canvas canvas, ui.Image image, Rect rect, BoxFit fit) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    if (fit == BoxFit.fill) {
      canvas.drawImageRect(
        image,
        src,
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    final dst = rect;
    final size = Size(
      rect.width <= 0 ? 1 : rect.width,
      rect.height <= 0 ? 1 : rect.height,
    );
    computeScaledRect(
      src: src,
      dst: Rect.fromLTWH(dst.left, dst.top, size.width, size.height),
      fit: fit,
    );
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(dst.left, dst.top, size.width, size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static Rect computeScaledRect({
    required Rect src,
    required Rect dst,
    required BoxFit fit,
  }) {
    if (src.isEmpty || dst.isEmpty) return dst;
    final srcAspect = src.width / src.height;
    final dstAspect = dst.width / dst.height;
    double w = dst.width;
    double h = dst.height;
    switch (fit) {
      case BoxFit.contain:
        if (srcAspect > dstAspect) {
          h = w / srcAspect;
        } else {
          w = h * srcAspect;
        }
      case BoxFit.cover:
        if (srcAspect > dstAspect) {
          w = h * srcAspect;
        } else {
          h = w / srcAspect;
        }
      default:
        break;
    }
    return Rect.fromLTWH(
      dst.left + (dst.width - w) / 2,
      dst.top + (dst.height - h) / 2,
      w,
      h,
    );
  }

  @override
  bool shouldRepaint(PptxSlidePainter oldDelegate) {
    return oldDelegate.slide != slide ||
        oldDelegate.scale != scale ||
        oldDelegate.images != images;
  }
}

/// A widget that renders one slide scaled to fit its parent, keeping the
/// slide's aspect ratio, inside a zoomable parent.
class PptxSlideView extends StatelessWidget {
  const PptxSlideView({super.key, required this.slide, required this.images});

  final PptxRenderSlide slide;

  /// Decoded images: key -1 is the slide background, 0..n are the shapes.
  final Map<int, ui.Image> images;

  @override
  Widget build(BuildContext context) {
    final aspect = slide.widthEmu / slide.heightEmu;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / slide.widthEmu;
              return CustomPaint(
                painter: PptxSlidePainter(
                  slide: slide,
                  scale: scale,
                  images: images,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- xml helpers -----------------------------------------------------------

/// Returns the shape's transform (`a:xfrm`), which lives inside `spPr` but
/// may occasionally be a direct child of the shape element.
XmlElement? _shapeXfrm(XmlElement element) {
  final spPr = _childByLocal(element, 'spPr');
  if (spPr != null) {
    final xfrm = _childByLocal(spPr, 'xfrm');
    if (xfrm != null) return xfrm;
  }
  return _childByLocal(element, 'xfrm');
}

String? _attr(XmlElement element, String name) {
  final local = name.split(':').last;
  for (final attribute in element.attributes) {
    if (attribute.name.local == local) return attribute.value;
  }
  return null;
}

bool _hasAncestor(XmlElement element, String local) {
  var parent = element.parent;
  while (parent is XmlElement) {
    if (parent.name.local == local) return true;
    parent = parent.parent;
  }
  return false;
}

XmlElement? _childByLocal(XmlElement element, String local) {
  for (final child in element.childElements) {
    if (child.name.local == local) return child;
  }
  return null;
}

List<XmlElement> _descendantsByLocal(XmlElement element, String local) {
  return element.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == local)
      .toList();
}

Color? _parseHexColor(String value) {
  final clean = value.replaceAll('#', '');
  if (clean.length != 6) return null;
  final parsed = int.tryParse(clean, radix: 16);
  if (parsed != null) return Color(0xFF000000 | parsed);
  return null;
}
