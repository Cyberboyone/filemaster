import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a list (Files or Recents) is in multi-select mode.
///
/// The home screen watches this to hide the floating "+" button so it
/// never covers the Share/Delete actions of the selection bar.
final selectionActiveProvider = StateProvider<bool>((ref) => false);