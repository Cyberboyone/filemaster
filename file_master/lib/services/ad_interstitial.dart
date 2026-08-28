import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdInterstitial {
  AdInterstitial._();

  static final AdInterstitial instance = AdInterstitial._();

  static const _adUnitId = 'ca-app-pub-9529770421530115/6030651876';

  InterstitialAd? _ad;
  bool _isLoading = false;

  bool _showWhenReady = false;
  VoidCallback? _pendingOnDone;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

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
      preload();
    }
  }

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
        preload();
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
