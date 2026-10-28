// The sound of moving between screens: a full screen opening plays the marimba's A4 to D5 (the Evochi call's
// first two notes), closing plays D5 to A4 (AudioService.nav). Sheets and dialogs keep their own taps.

import 'package:flutter/widgets.dart';

import 'audio_service.dart';

class NavSound extends NavigatorObserver {
  NavSound(this.audio);

  final AudioService Function() audio;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) audio().nav(forward: true);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute && oldRoute != null) audio().nav(forward: true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) audio().nav(forward: false);
  }
}
