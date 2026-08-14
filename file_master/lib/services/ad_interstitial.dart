import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Pre-loads and shows interstitial ads after key user actions.
///
/// Call [preload] early (e.g. on app start or after each show) so the next
/// ad is ready when needed. Call [show] after a completed action; if the ad
/// isn't loaded yet, the [onDone] callback fires immediately.
///
class AdInterstitial {
  AdInterstitial._();

  static final AdInterstitial instance = AdInterstitial._();

  static const _adUnitId = 'ca-app-pub-9529770421530115/6030651876';

  InterstitialAd? _ad;
  bool _isLoading = false;

  /// Start loading the next interstitial in the background.
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
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: ${error.message}');
          _isLoading = false;
        },
      ),
    );
  }

  /// Show a full-screen interstitial. [onDone] is called after the ad closes
  /// (or immediately if the ad isn't ready).
  void show({required VoidCallback onDone}) {
    final ad = _ad;
    if (ad == null) {
      onDone();
      return;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        preload(); // start loading the next one
        onDone();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial failed to show: ${error.message}');
        ad.dispose();
        _ad = null;
        onDone();
      },
    );
    ad.show();
    _ad = null;
  }
}
