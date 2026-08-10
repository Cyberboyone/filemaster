import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:file_master/utils/pptx_renderer.dart';

/// 1x1 transparent PNG.
final Uint8List _tinyPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

const _nsP =
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const _nsA = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
const _nsR =
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

String _slideXml({String? picPart, String? extraShape = ''}) {
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld $_nsP $_nsA $_nsR>
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Box"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="914400" y="914400"/><a:ext cx="1828800" cy="914400"/></a:xfrm>
          <a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>
        </p:spPr>
        <p:txBody>
          <a:bodyPr lIns="91440" tIns="45720"/>
          <a:lstStyle/>
          <a:p>
            <a:pPr algn="ctr"/>
            <a:r><a:rPr sz="2400" b="1"><a:solidFill><a:srgbClr val="00FF00"/></a:solidFill></a:rPr><a:t>Hello Slide</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
      $picPart
      $extraShape
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>
''';
}

String _presentationXml() {
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation $_nsP $_nsA $_nsR>
  <p:sldIdLst>
    <p:sldId id="256" r:id="rId1"/>
    <p:sldId id="257" r:id="rId2"/>
  </p:sldIdLst>
  <p:sldSz cx="12192000" cy="6858000"/>
</p:presentation>
''';
}

List<int> _zip(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive)!;
}

Uint8List _buildPptx({bool withImage = false}) {
  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
    ),
    'ppt/presentation.xml': utf8.encode(_presentationXml()),
    'ppt/slides/slide0.xml': utf8.encode(_slideXml()),
    'ppt/slides/_rels/slide0.xml.rels': utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
'''),
    'ppt/slides/slide1.xml': utf8.encode(
      _slideXml(
        picPart: withImage
            ? '''
      <p:pic>
        <p:nvPicPr><p:cNvPr id="3" name="Pic"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rIdPic"/>
          <a:stretch><a:fillRect/></a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm>
        </p:spPr>
      </p:pic>'''
            : '',
      ),
    ),
  };
  if (withImage) {
    files['ppt/slides/_rels/slide1.xml.rels'] = utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdPic" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
</Relationships>
''');
    files['ppt/media/image1.png'] = _tinyPng;
  }
  return Uint8List.fromList(_zip(files));
}

void main() {
  test('parsePptxRender parses slides, shapes, fills and run styling', () {
    final slides = parsePptxRender(_buildPptx());

    expect(slides, hasLength(2));
    final slide = slides[0];
    expect(slide.widthEmu, 12192000);
    expect(slide.heightEmu, 6858000);
    expect(slide.hasContent, isTrue);

    expect(slide.shapes, hasLength(1));
    final shape = slide.shapes.single;
    expect(shape.xEmu, 914400);
    expect(shape.yEmu, 914400);
    expect(shape.widthEmu, 1828800);
    expect(shape.heightEmu, 914400);
    expect(shape.fillColor, const Color(0xFFFF0000));

    final line = shape.lines.single;
    expect(line.text, 'Hello Slide');
    expect(line.sizePt, 24);
    expect(line.bold, isTrue);
    expect(line.color, const Color(0xFF00FF00));
    expect(line.align, 'ctr');
    expect(line.leftInsetEmu, 91440);
    expect(line.topInsetEmu, 45720);
  });

  test('parsePptxRender resolves picture images through slide rels', () {
    final slides = parsePptxRender(_buildPptx(withImage: true));

    final slide = slides[1];
    expect(slide.shapes, hasLength(2));
    final pic = slide.shapes.firstWhere((shape) => shape.imageBytes != null);
    expect(pic.imageBytes, isNotNull);
    expect(pic.imageBytes!.length, greaterThan(0));
  });

  test('parsePptxRender throws for corrupt bytes', () {
    expect(
      () => parsePptxRender(Uint8List.fromList(List.filled(32, 0x00))),
      throwsFormatException,
    );
  });

  test('empty presentation with no slides reports no content', () {
    final files = <String, List<int>>{
      'ppt/presentation.xml': utf8.encode(_presentationXmlWithoutSlides()),
      'ppt/slides/slide0.xml': utf8.encode(_slideXml()),
      'ppt/slides/_rels/slide0.xml.rels': utf8.encode(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>',
      ),
    };
    final slides = parsePptxRender(Uint8List.fromList(_zip(files)));
    expect(slides, isEmpty);
  });
}

String _presentationXmlWithoutSlides() {
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation $_nsP $_nsA $_nsR>
  <p:sldIdLst/>
  <p:sldSz cx="12192000" cy="6858000"/>
</p:presentation>
''';
}
