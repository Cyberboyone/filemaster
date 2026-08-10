import 'package:flutter/material.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';

import 'package:file_master/utils/text_pager.dart';

const _style = TextStyle(fontSize: 14, height: 1.4);

void main() {
  test('empty text produces a single empty page', () {
    final pages = paginateText(
      text: '',
      style: _style,
      width: 300,
      height: 200,
    );
    expect(pages, ['']);
  });

  test('whitespace only text produces a single clean page', () {
    final pages = paginateText(
      text: '  \n \n ',
      style: _style,
      width: 300,
      height: 200,
    );
    expect(pages, ['']);
  });

  test('short text stays on one page and is preserved', () {
    const text = 'A short essay about file mastering.\nSecond line.';
    final pages = paginateText(
      text: text,
      style: _style,
      width: 300,
      height: 200,
    );
    expect(pages, hasLength(1));
    expect(pages.single, text);
  });

  test('long text splits into multiple pages without losing content', () {
    final text = List.generate(
      300,
      (i) => 'Line number $i of the document',
    ).join('\n');
    final pages = paginateText(
      text: text,
      style: _style,
      width: 200,
      height: 120,
    );
    expect(pages.length, greaterThan(1));
    expect(pages.join(), text);
  });

  test('a single over-tall line still becomes a page', () {
    final pages = paginateText(
      text: 'a' * 5000,
      style: _style,
      width: 300,
      height: 30,
    );
    expect(pages, isNotEmpty);
    expect(pages.join(), 'a' * 5000);
  });
}
