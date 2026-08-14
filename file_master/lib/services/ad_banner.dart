import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner ad shown above the bottom navigation bar.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  static const _bannerAdUnitId = 'ca-app-pub-9529770421530115/1726896626';

  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    _ad = ad;
    ad.load();
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
    // Give the AdWidget a definite size. Without an explicit height the
    // underlying platform view can be created with an invalid (zero/NaN)
    // transform, which logs "TransformLayer is constructed with an invalid
    // matrix" and blanks the surrounding UI on some devices.
    return Container(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      color: Theme.of(context).colorScheme.surface,
      child: AdWidget(ad: ad),
    );
  }
}
