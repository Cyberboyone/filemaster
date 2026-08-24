import 'package:flutter/material.dart';

/// Global navigator key so platform channels (e.g. incoming shared files) can
/// push routes without a BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
