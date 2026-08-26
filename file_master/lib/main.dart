import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'models/recent_file.dart';
import 'navigation.dart';
import 'providers/recents_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/viewer_screen.dart';
import 'services/ad_interstitial.dart';
import 'utils/doc_format.dart';

const String kFileOpenChannel = 'com.nakudin.filemaster/file_open';

/// Shared application container, also used by platform channel handlers.
late final ProviderContainer appContainer;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  unawaited(MobileAds.instance.initialize());
  AdInterstitial.instance.startConnectivityAwarePreload();

  appContainer = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  runApp(
    UncontrolledProviderScope(
      container: appContainer,
      child: const FileMasterApp(),
    ),
  );

  _setupFileOpenChannel();
}

void _setupFileOpenChannel() {
  final channel = const MethodChannel(kFileOpenChannel);
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onFileOpened') {
      final args = call.arguments;
      if (args is Map) _openSharedFile(_asStringMap(args));
    }
    return null;
  });

  // Pull any file the app was launched with (cold start via a file intent).
  unawaited(
    channel.invokeMethod<dynamic>('getInitialFile').then((value) {
      if (value is Map) _openSharedFile(_asStringMap(value));
    }).catchError((_) {
      // Native handler not ready yet – not fatal.
    }),
  );
}

Map<String, dynamic> _asStringMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

void _openSharedFile(Map<String, dynamic> map) {
  final path = map['path'] as String?;
  if (path == null || path.isEmpty) return;
  final file = File(path);
  if (!file.existsSync()) return;
  var name = (map['name'] as String?) ?? p.basename(path);
  final mime = (map['mime'] as String?) ?? '';
  if (!name.contains('.') && mime.isNotEmpty) {
    final ext = _extensionFromMime(mime);
    if (ext != null) name = '$name.$ext';
  }
  final recent = RecentFile(
    name: name,
    path: path,
    format: DocFormat.fromPath(name),
    sizeBytes: file.lengthSync(),
    lastOpened: DateTime.now(),
  );
  unawaited(
    appContainer.read(recentsControllerProvider.notifier).recordOpen(recent),
  );
  _navigateToShared(recent);
}

/// Best-effort map from a mime type to a file extension, mirroring the native
/// side, so format detection works even if the shared file has no extension.
String? _extensionFromMime(String mime) {
  const map = <String, String>{
    'application/pdf': 'pdf',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        'docx',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        'pptx',
    'application/rtf': 'rtf',
    'application/vnd.oasis.opendocument.text': 'odt',
    'application/vnd.oasis.opendocument.spreadsheet': 'ods',
    'application/vnd.oasis.opendocument.presentation': 'odp',
    'text/plain': 'txt',
    'text/csv': 'csv',
    'application/zip': 'zip',
    'application/x-rar-compressed': 'rar',
    'application/x-7z-compressed': '7z',
    'application/gzip': 'gz',
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/gif': 'gif',
    'image/bmp': 'bmp',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'image/tiff': 'tiff',
  };
  return map[mime];
}

int _pendingNavigations = 0;

void _navigateToShared(RecentFile recent) {
  final state = navigatorKey.currentState;
  if (state != null) {
    state.push(MaterialPageRoute(builder: (_) => ViewerScreen(file: recent)));
    return;
  }
  // Navigator not mounted yet (cold start) – retry briefly until it is.
  if (_pendingNavigations++ < 20) {
    Future.delayed(
      const Duration(milliseconds: 100),
      () => _navigateToShared(recent),
    );
  }
}
