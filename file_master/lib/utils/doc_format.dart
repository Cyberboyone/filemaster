import 'package:flutter/material.dart';

enum DocFormat {
  pdf('PDF', 'pdf', Icons.picture_as_pdf),
  word('Word', 'word', Icons.description),
  excel('Excel', 'excel', Icons.table_chart),
  powerpoint('PowerPoint', 'powerpoint', Icons.slideshow),
  text('Text', 'text', Icons.article),
  image('Image', 'image', Icons.image_outlined),
  archive('Archive', 'archive', Icons.folder_zip),
  other('File', 'other', Icons.insert_drive_file);

  const DocFormat(this.label, this.storageKey, this.icon);

  final String label;
  final String storageKey;
  final IconData icon;

  static DocFormat fromPath(String path) {
    final ext = path.toLowerCase();
    if (ext.endsWith('.pdf')) return DocFormat.pdf;
    if (ext.endsWith('.doc') ||
        ext.endsWith('.docx') ||
        ext.endsWith('.odt') ||
        ext.endsWith('.rtf')) {
      return DocFormat.word;
    }
    if (ext.endsWith('.xls') ||
        ext.endsWith('.xlsx') ||
        ext.endsWith('.csv') ||
        ext.endsWith('.ods')) {
      return DocFormat.excel;
    }
    if (ext.endsWith('.ppt') || ext.endsWith('.pptx') || ext.endsWith('.odp')) {
      return DocFormat.powerpoint;
    }
    if (ext.endsWith('.txt') ||
        ext.endsWith('.md') ||
        ext.endsWith('.log') ||
        ext.endsWith('.json')) {
      return DocFormat.text;
    }
    const images = [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.tiff',
    ];
    for (final image in images) {
      if (ext.endsWith(image)) return DocFormat.image;
    }
    const archives = ['.zip', '.rar', '.7z', '.tar', '.gz'];
    for (final archive in archives) {
      if (ext.endsWith(archive)) return DocFormat.archive;
    }
    return DocFormat.other;
  }

  static DocFormat fromStorageKey(String key) {
    for (final format in DocFormat.values) {
      if (format.storageKey == key) return format;
    }
    return DocFormat.other;
  }
}
