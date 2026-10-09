// Privacy-conscious product events (style guide §25). Only with consent; never raw health data.

import 'package:flutter/foundation.dart';

class Analytics {
  bool consent = false;
  final List<Map<String, Object?>> buffer = [];

  void track(String name, [Map<String, Object?> props = const {}]) {
    if (!consent) return;
    final e = {'name': name, 't': DateTime.now().millisecondsSinceEpoch, ...props};
    buffer.add(e);
    if (buffer.length > 200) buffer.removeAt(0);
    if (kDebugMode) debugPrint('[analytics] $e');
  }
}
