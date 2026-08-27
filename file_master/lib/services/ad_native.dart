import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const String nativeAdUnitId = 'ca-app-pub-9529770421530115/1144465742';

/// Native ad (small template) shown in a bottom slot instead of interstitials.
///
/// Loads lazily, renders via [AdWidget] once ready, and disposes the
/// underlying platform ad on unmount to avoid leaks.
class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key, this.height = 120});

  final double height;

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Native ad failed to load: ${error.message}');
          ad.dispose();
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Colors.white,
        primaryTextStyle: NativeTemplateTextStyle(
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(size: 12),
        callToActionTextStyle: NativeTemplateTextStyle(
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    // Give AdWidget a definite size so the underlying platform view is not
    // created with an invalid transform (which blanks surrounding UI).
    return Container(
      width: double.infinity,
      height: widget.height,
      color: Theme.of(context).colorScheme.surface,
      child: AdWidget(ad: ad),
    );
  }
}
