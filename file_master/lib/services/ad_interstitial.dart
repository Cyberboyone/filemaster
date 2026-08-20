import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Pre-loads and shows interstitial ads after key user actions and on app open.
///
/// [startConnectivityAwarePreload] keeps an ad ready in the background
/// whenever the device has connectivity (including mobile data), so the
/// next interstitial can be shown instantly. [showAppOpen] displays the ad
/// when the app is opened; if the ad isn't ready yet it is shown as soon as
/// it finishes loading.
class AdInterstitial {
  AdInterstitial._();

  static final AdInterstitial instance = AdInterstitial._();

  static const _adUnitId = 'ca-app-pub-9529770421530115/6030651876';

  InterstitialAd? _ad;
  bool _isLoading = false;

  // App-open queue: show as soon as the next ad is ready.
  bool _showWhenReady = false;
  VoidCallback? _pendingOnDone;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Start loading the next interstitial in the background. Safe to call
  /// repeatedly; it is a no-op while one is already loaded or loading.
  void preload() {
    if (_ad != null || _isLoading) return;
    _isLoading = true;
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
          if (_showWhenReady) {
            _showWhenReady = false;
            _show(ad);
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: ${error.message}');
          _isLoading = false;
        },
      ),
    );
  }

  /// Keep an interstitial preloaded in the background whenever the device is
  /// online (WiFi or mobile data). Call this once at startup so ads are ready
  /// to show the moment the app is opened.
  void startConnectivityAwarePreload() {
    _preloadIfConnected();
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
      _preloadIfConnected();
    });
  }

  Future<void> _preloadIfConnected() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) preload();
    } catch (_) {
      // If connectivity can't be determined, try to load anyway.
      preload();
    }
  }

  /// Show a full-screen interstitial when the app is opened. If an ad isn't
  /// ready yet it will be shown as soon as it finishes loading in the
  /// background.
  void showAppOpen({required VoidCallback onDone}) {
    final ad = _ad;
    if (ad != null) {
      _show(ad, onDone);
      return;
    }
    _showWhenReady = true;
    _pendingOnDone = onDone;
    preload();
  }

  /// Show a full-screen interstitial after a completed action. If the ad
  /// isn't ready, [onDone] fires immediately.
  void show({required VoidCallback onDone}) {
    final ad = _ad;
    if (ad == null) {
      onDone();
      return;
    }
    _show(ad, onDone);
  }

  void _show(InterstitialAd ad, [VoidCallback? onDone]) {
    final cb = onDone ?? _pendingOnDone;
    _pendingOnDone = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        ad.dispose();
        _ad = null;
        preload(); // start loading the next one
        cb?.call();
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        debugPrint('Interstitial failed to show: ${error.message}');
        ad.dispose();
        _ad = null;
        cb?.call();
      },
    );
    ad.show();
    _ad = null;
  }
}
