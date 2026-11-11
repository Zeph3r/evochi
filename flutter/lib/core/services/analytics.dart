// Privacy-conscious product events (style guide §25). Only with consent; never raw health data.
//
// Every event also goes into the diagnostics log on the phone (whatever the consent toggle says: the log
// only leaves the device when the player sends a problem report from Settings). Sending events to a
// backend is still to come (NEXT_STEPS.md "Beta launch"); until then [buffer] is the consented queue.

import 'diagnostics.dart';

class Analytics {
  bool consent = false;
  final List<Map<String, Object?>> buffer = [];

  void track(String name, [Map<String, Object?> props = const {}]) {
    Log.event(name, props);
    if (!consent) return;
    final e = {'name': name, 't': DateTime.now().millisecondsSinceEpoch, ...props};
    buffer.add(e);
    if (buffer.length > 200) buffer.removeAt(0);
  }
}
