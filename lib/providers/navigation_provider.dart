import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-navigation tabs. The Dashboard tab is gone — device status now
/// sits in a strip at the top of the Library, which is the app's home.
class HomeTab {
  const HomeTab._();

  static const library = 0;
  static const stats = 1;
  static const settings = 2;
}

final navigationIndexProvider = StateProvider<int>((ref) => HomeTab.library);
