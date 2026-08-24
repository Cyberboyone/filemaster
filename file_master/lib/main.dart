import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
  final name = (map['name'] as String?) ?? p.basename(path);
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
