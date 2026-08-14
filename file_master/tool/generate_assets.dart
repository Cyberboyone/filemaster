// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  _generateAppIcon();
  _generateAdaptiveIconForeground();
  _generateSplashLogo();
  _generateSplashLogoDark();
  print('Assets generated successfully.');
}

img.Image _makeIcon(int size, img.Color bgColor, img.Color docColor,
    img.Color foldColor, img.Color letterColor) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: bgColor);

  // Document body (rounded rectangle via radius param).
  final docX = (size * 0.23).toInt();
  final docY = (size * 0.14).toInt();
  final docW = (size * 0.54).toInt();
  final docH = (size * 0.67).toInt();
  final radius = (size * 0.06).toInt();

  img.fillRect(image, x1: docX, y1: docY, x2: docX + docW, y2: docY + docH,
      color: docColor, radius: radius);

  // Dog-ear fold (triangle in top-right corner).
  final foldX = docX + docW - (size * 0.14).toInt();
  img.fillPolygon(image, vertices: [
    img.Point(foldX, docY),
    img.Point(docX + docW, docY),
    img.Point(docX + docW, docY + (size * 0.14).toInt()),
  ], color: foldColor);

  // "F" letter.
  _drawF(image, (docX + docW * 0.28).toInt(), (docY + docH * 0.18).toInt(),
      (docW * 0.48).toInt(), (docH * 0.48).toInt(), letterColor);

  // "M" letter.
  _drawM(image, (docX + docW * 0.38).toInt(), (docY + docH * 0.52).toInt(),
      (docW * 0.44).toInt(), (docH * 0.36).toInt(), letterColor);

  return image;
}

void _generateAppIcon() {
  final image = _makeIcon(512, img.ColorRgb8(0x1A, 0x23, 0x7E),
      img.ColorRgb8(255, 255, 255), img.ColorRgb8(200, 210, 240),
      img.ColorRgb8(0x1A, 0x23, 0x7E));
  File('assets/icon/app_icon.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  print('  -> assets/icon/app_icon.png');
}

void _generateAdaptiveIconForeground() {
  // Adaptive icons: 432px canvas with 72% safe zone (~310px).
  final image = img.Image(width: 432, height: 432);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0)); // transparent bg

  final pad = 61; // (432 - 310) ~/ 2
  final bgColor = img.ColorRgb8(0x1A, 0x23, 0x7E);
  final docColor = img.ColorRgb8(255, 255, 255);
  final foldColor = img.ColorRgb8(200, 210, 240);
  final letterColor = img.ColorRgb8(0x1A, 0x23, 0x7E);

  // Background rounded square.
  img.fillRect(image, x1: pad, y1: pad, x2: 432 - pad, y2: 432 - pad,
      color: bgColor, radius: 40);

  // Document.
  final docX = pad + 30;
  final docY = pad + 20;
  final docW = 250;
  final docH = 270;
  img.fillRect(image, x1: docX, y1: docY, x2: docX + docW, y2: docY + docH,
      color: docColor, radius: 20);

  // Dog-ear fold.
  img.fillPolygon(image, vertices: [
    img.Point(docX + docW - 50, docY),
    img.Point(docX + docW, docY),
    img.Point(docX + docW, docY + 50),
  ], color: foldColor);

  // "F" and "M" letters.
  _drawF(image, docX + 40, docY + 50, 100, 160, letterColor);
  _drawM(image, docX + 60, docY + 130, 90, 120, letterColor);

  File('assets/icon/app_icon_foreground.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  print('  -> assets/icon/app_icon_foreground.png');
}

void _generateSplashLogo() {
  final image = _makeIcon(300, img.ColorRgba8(0, 0, 0, 0),
      img.ColorRgb8(255, 255, 255), img.ColorRgb8(200, 210, 240),
      img.ColorRgb8(0x1A, 0x23, 0x7E));
  File('assets/splash/splash_logo.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  print('  -> assets/splash/splash_logo.png');
}

void _generateSplashLogoDark() {
  final image = _makeIcon(300, img.ColorRgba8(0, 0, 0, 0),
      img.ColorRgb8(200, 210, 240), img.ColorRgb8(140, 155, 190),
      img.ColorRgb8(255, 255, 255));
  File('assets/splash/splash_logo_dark.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  print('  -> assets/splash/splash_logo_dark.png');
}

void _drawF(img.Image image, int x, int y, int w, int h, img.Color color) {
  final barW = (w * 0.28).toInt();
  final hBarW = (w * 0.65).toInt();
  final hBarH = (h * 0.16).toInt();
  final midH = (h * 0.08).toInt();

  img.fillRect(image, x1: x, y1: y, x2: x + barW, y2: y + h, color: color);
  img.fillRect(image, x1: x, y1: y, x2: x + hBarW, y2: y + hBarH, color: color);
  img.fillRect(image, x1: x, y1: (y + h * 0.40).toInt(),
      x2: x + (hBarW * 0.80).toInt(),
      y2: (y + h * 0.40 + midH).toInt(), color: color);
}

void _drawM(img.Image image, int x, int y, int w, int h, img.Color color) {
  final barW = (w * 0.22).toInt();

  // Left stem.
  img.fillRect(image, x1: x, y1: y, x2: x + barW, y2: y + h, color: color);
  // Right stem.
  img.fillRect(image, x1: x + w - barW, y1: y, x2: x + w, y2: y + h,
      color: color);
  // Left slant.
  img.fillPolygon(image, vertices: [
    img.Point(x, y),
    img.Point(x + barW, y),
    img.Point((x + w * 0.5).toInt(), (y + h * 0.55).toInt()),
  ], color: color);
  // Right slant.
  img.fillPolygon(image, vertices: [
    img.Point(x + w, y),
    img.Point(x + w - barW, y),
    img.Point((x + w * 0.5).toInt(), (y + h * 0.55).toInt()),
  ], color: color);
}
