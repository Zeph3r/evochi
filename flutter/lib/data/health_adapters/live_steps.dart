// The phone's own step counter, live (Android: MainActivity.kt's "evochi/steps" channels; elsewhere nothing).
//
// Health Connect only hears of your steps when the phone's step tracker writes them in, which can be minutes
// later, so the first hatch counts from the counter itself while its screen is open. Nothing here is stored or
// sent anywhere: the game's record of your steps (XP, quests, the rest) still comes from Health Connect, and the
// hatch takes whichever count is higher, so a step is never counted twice.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class LiveSteps {
  static const _ask = MethodChannel('evochi/steps');
  static const _live = EventChannel('evochi/steps/live');

  /// Whether the phone has a step counter we may read (asking for the physical-activity permission if needed).
  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    try {
      if (await _ask.invokeMethod<bool>('available') != true) return false;
      return await _ask.invokeMethod<bool>('permission') == true;
    } catch (_) {
      return false;
    }
  }

  /// Steps taken since listening began, as they happen (the counter's first reading is the starting point).
  static Stream<int> since() {
    int? first;
    return _live.receiveBroadcastStream().map((v) {
      final n = (v as num).toInt();
      first ??= n;
      return n - first!;
    });
  }
}
