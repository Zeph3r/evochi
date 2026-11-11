// Diagnostics for the beta: a log kept on the phone, every error and crash caught and written down, the
// frames that stutter counted, and all of it folded into one report a player can send from Settings
// ("Report a problem"). Nothing here leaves the device on its own: the report goes when the player sends
// it, and a crash reporter (Firebase Crashlytics, planned: NEXT_STEPS.md "Beta launch") plugs in behind
// [CrashReporter] once the project exists. Never health data: the log carries game events and errors.
//
//   Log.i('wilds', 'floor 3 loaded')          a line in the ring buffer (the last [Log.keep] are kept)
//   Diagnostics.install(build: '123')         before runApp: the error handlers, the frame watch, the
//                                             last session's log read back (did it end cleanly?)
//   Diagnostics.screen = 'wilds'              what is up, for the frame watch and the report
//   Diagnostics.report(error, stack)          an error worth a record (non-fatal); fatal ones come
//                                             through the handlers on their own
//   Diagnostics.flush(clean: true)            on pause: the log's tail and the "ended cleanly" mark to disk
//   DiagnosticsReport.text(...)               the report: build, device, screen, last crash, jank, events, log

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogLine {
  const LogLine(this.t, this.level, this.tag, this.msg);
  final DateTime t;
  final String level, tag, msg;

  @override
  String toString() {
    final hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0'), ss = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms $level $tag: $msg';
  }
}

/// The ring buffer: the last [keep] lines of what the app did, newest last.
class Log {
  Log._();
  static const keep = 600;
  static final lines = <LogLine>[];
  static final _listeners = <void Function(LogLine)>[];

  static void i(String tag, String msg) => _add('I', tag, msg);
  static void w(String tag, String msg) => _add('W', tag, msg);
  static void e(String tag, String msg) => _add('E', tag, msg);

  /// A product event (analytics.dart): in the log whatever the sharing toggle says, since the log only
  /// leaves the phone when the player sends a report.
  static void event(String name, Map<String, Object?> props) => _add('I', 'event', props.isEmpty ? name : '$name $props');

  static void _add(String level, String tag, String msg) {
    final line = LogLine(DateTime.now(), level, tag, msg.length > 600 ? '${msg.substring(0, 600)}…' : msg);
    lines.add(line);
    if (lines.length > keep) lines.removeRange(0, lines.length - keep);
    for (final l in _listeners) {
      l(line);
    }
    if (kDebugMode) debugPrint(line.toString());
  }

  /// A crash reporter's breadcrumbs, say.
  static void listen(void Function(LogLine) l) => _listeners.add(l);

  static String tail([int n = 200]) => lines.skip(lines.length > n ? lines.length - n : 0).map((l) => l.toString()).join('\n');
}

/// Where a caught error goes: the local record always; a cloud reporter too once one is plugged in.
abstract class CrashReporter {
  Future<void> record(Object error, StackTrace? stack, {bool fatal = false, String? context});
  Future<void> setKey(String key, Object value);
}

/// One error written down on the phone (for the report; the last few are kept).
class CrashRecord {
  const CrashRecord(this.t, this.error, this.stack, this.fatal, this.screen, this.logTail);
  final DateTime t;
  final String error, stack, screen, logTail;
  final bool fatal;

  Map<String, Object?> toJson() => {'t': t.millisecondsSinceEpoch, 'error': error, 'stack': stack, 'fatal': fatal, 'screen': screen, 'log': logTail};

  static CrashRecord fromJson(Map<String, dynamic> j) => CrashRecord(
        DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        j['error'] as String? ?? '',
        j['stack'] as String? ?? '',
        j['fatal'] as bool? ?? false,
        j['screen'] as String? ?? '',
        j['log'] as String? ?? '',
      );
}

/// The reporter the app always has: errors go to the log and to a short list on disk.
class LocalCrashReporter implements CrashReporter {
  static const keep = 5;
  final records = <CrashRecord>[];
  final keys = <String, Object>{};

  @override
  Future<void> record(Object error, StackTrace? stack, {bool fatal = false, String? context}) async {
    final rec = CrashRecord(DateTime.now(), '${context == null ? '' : '$context: '}$error', (stack ?? StackTrace.empty).toString(), fatal,
        Diagnostics.screen, Log.tail(80));
    records.add(rec);
    if (records.length > keep) records.removeAt(0);
    await Diagnostics._saveCrashes();
  }

  @override
  Future<void> setKey(String key, Object value) async => keys[key] = value;
}

/// Frames that stutter: counted per screen, a line in the log every so often while it goes on.
class JankWatch {
  JankWatch._();
  static const slowMs = 32; // two frames at 60 Hz: what a player sees as a hitch
  static int _frames = 0, _slow = 0, _worst = 0;
  static DateTime _since = DateTime.now();
  static final perScreen = <String, ({int frames, int slow, int worst})>{};
  static bool _on = false;

  static void start() {
    if (_on) return;
    _on = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMilliseconds;
      _frames++;
      if (ms > slowMs) _slow++;
      if (ms > _worst) _worst = ms;
    }
    final sc = perScreen[Diagnostics.screen] ?? (frames: 0, slow: 0, worst: 0);
    perScreen[Diagnostics.screen] = (
      frames: sc.frames + timings.length,
      slow: sc.slow + timings.where((t) => t.totalSpan.inMilliseconds > slowMs).length,
      worst: timings.fold(sc.worst, (w, t) => t.totalSpan.inMilliseconds > w ? t.totalSpan.inMilliseconds : w),
    );
    final now = DateTime.now();
    if (now.difference(_since).inSeconds >= 10) {
      if (_slow > 0) Log.w('frames', '${Diagnostics.screen}: $_slow of $_frames frames over ${slowMs}ms in ${now.difference(_since).inSeconds}s, worst ${_worst}ms');
      _frames = _slow = _worst = 0;
      _since = now;
    }
  }

  static String summary() => perScreen.entries
      .where((e) => e.value.frames > 0)
      .map((e) => '${e.key}: ${e.value.slow}/${e.value.frames} slow, worst ${e.value.worst}ms')
      .join('; ');
}

class Diagnostics {
  Diagnostics._();
  static const _logKey = 'evochi.diag.lastlog.v1', _crashKey = 'evochi.diag.crashes.v1';

  /// What is up: 'nest', 'wilds', 'market'... (screens set it; the frame watch and the report read it).
  static String screen = 'app';
  static String build = 'dev';
  static final local = LocalCrashReporter();

  /// A cloud reporter, when one is plugged in (NEXT_STEPS.md "Beta launch": Firebase Crashlytics).
  static CrashReporter? cloud;

  /// The last session's log tail and whether it ended cleanly (paused or closed by the player), read back
  /// at start. Not clean: the app died while it was up (a crash, or the OS killing it in the foreground).
  static String? lastSessionLog;
  static bool lastSessionClean = true;
  static DateTime? lastSessionAt;
  static bool _installed = false;

  /// Before runApp: the error handlers, the frame watch, the last session read back.
  static Future<void> install({required String build}) async {
    if (_installed) return;
    _installed = true;
    Diagnostics.build = build;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(details.exception, details.stack, context: details.context?.toDescription() ?? 'flutter', fatal: false);
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, fatal: true, context: 'uncaught');
      return true;
    };
    try {
      final p = await SharedPreferences.getInstance();
      final last = p.getString(_logKey);
      if (last != null) {
        final nl = last.indexOf('\n');
        final head = nl < 0 ? last : last.substring(0, nl);
        // the first line: "clean|<ms>" or "live|<ms>"
        final parts = head.split('|');
        lastSessionClean = parts.first == 'clean';
        lastSessionAt = parts.length > 1 ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[1]) ?? 0) : null;
        lastSessionLog = nl < 0 ? '' : last.substring(nl + 1);
      }
      final crashes = p.getStringList(_crashKey) ?? const [];
      for (final c in crashes) {
        try {
          local.records.add(CrashRecord.fromJson((jsonDecode(c) as Map).cast<String, dynamic>()));
        } catch (_) {}
      }
    } catch (_) {}
    Log.i('app', 'start: build $build, ${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
        '${lastSessionClean ? '' : ' (the last session did not end cleanly)'}');
    JankWatch.start();
    // this session is live until a pause says otherwise
    unawaited(flush(clean: false));
  }

  /// An error worth a record. Fatal ones come through the handlers; call this for the ones caught and
  /// recovered from that should still be known about.
  static void report(Object error, StackTrace? stack, {bool fatal = false, String? context}) {
    Log.e(fatal ? 'crash' : 'error', '${context == null ? '' : '$context: '}$error');
    unawaited(local.record(error, stack, fatal: fatal, context: context));
    final c = cloud;
    if (c != null) unawaited(c.record(error, stack, fatal: fatal, context: context).catchError((_) {}));
    if (fatal) unawaited(flush(clean: false));
  }

  /// The log's tail and the session's state to disk: [clean] when the app is pausing or closing on its own,
  /// so a next start can tell a crash from a goodbye.
  static Future<void> flush({required bool clean}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_logKey, '${clean ? 'clean' : 'live'}|${DateTime.now().millisecondsSinceEpoch}\n${Log.tail(200)}');
    } catch (_) {}
  }

  static Future<void> _saveCrashes() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_crashKey, [for (final r in local.records) jsonEncode(r.toJson())]);
    } catch (_) {}
  }

  static Future<void> clearCrashes() async {
    local.records.clear();
    await _saveCrashes();
  }
}
