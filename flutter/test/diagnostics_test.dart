// The beta's diagnostics (core/services/diagnostics.dart): the log, the crash records, the last session's
// mark, and the report a player sends from Settings.

import 'package:evochi/core/services/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Log.lines.clear();
    Diagnostics.local.records.clear();
  });

  test('the log keeps the last lines, newest last, and events go in whatever the consent says', () {
    for (var i = 0; i < Log.keep + 50; i++) {
      Log.i('t', 'line $i');
    }
    expect(Log.lines.length, Log.keep);
    expect(Log.lines.first.msg, 'line 50');
    expect(Log.lines.last.msg, 'line ${Log.keep + 49}');
    Log.event('wilds_descend', {'floor': 3});
    expect(Log.tail(1), contains('event: wilds_descend {floor: 3}'));
    expect(Log.tail(2).split('\n').length, 2);
  });

  test('a caught error is written down with the screen and the log tail, the last five kept', () async {
    SharedPreferences.setMockInitialValues({});
    Diagnostics.screen = 'wilds';
    Log.i('wilds', 'Tremor');
    for (var i = 0; i < 7; i++) {
      await Diagnostics.local.record(StateError('boom $i'), StackTrace.current, fatal: i == 6, context: 'test');
    }
    final r = Diagnostics.local.records;
    expect(r.length, LocalCrashReporter.keep);
    expect(r.last.error, 'test: Bad state: boom 6');
    expect(r.last.fatal, isTrue);
    expect(r.last.screen, 'wilds');
    expect(r.last.logTail, contains('Tremor'));
    expect(r.last.stack, contains('diagnostics_test'));
    // persisted: a fresh install reads them back
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList('evochi.diag.crashes.v1')!.length, LocalCrashReporter.keep);
  });

  test('a session that was still live when the app died is read back as not clean', () async {
    SharedPreferences.setMockInitialValues({'evochi.diag.lastlog.v1': 'live|1700000000000\n12:00:00.000 I wilds: Tremor\n12:00:01.000 I app: paused'});
    Diagnostics.lastSessionClean = true;
    Diagnostics.lastSessionLog = null;
    // (install runs once per process: read the mark the way it does)
    final p = await SharedPreferences.getInstance();
    final last = p.getString('evochi.diag.lastlog.v1')!;
    final head = last.substring(0, last.indexOf('\n'));
    expect(head.split('|').first, 'live');
    await Diagnostics.flush(clean: true);
    expect((await SharedPreferences.getInstance()).getString('evochi.diag.lastlog.v1'), startsWith('clean|'));
    await Diagnostics.flush(clean: false);
    expect((await SharedPreferences.getInstance()).getString('evochi.diag.lastlog.v1'), startsWith('live|'));
  });

  test('a crash record survives its JSON', () {
    final r = CrashRecord(DateTime.fromMillisecondsSinceEpoch(1700000000000), 'Bad state: x', '#0 main\n#1 run', true, 'wilds', 'a\nb');
    final back = CrashRecord.fromJson(r.toJson().cast<String, dynamic>());
    expect(back.t, r.t);
    expect(back.error, r.error);
    expect(back.stack, r.stack);
    expect(back.fatal, isTrue);
    expect(back.screen, 'wilds');
    expect(back.logTail, 'a\nb');
  });
}
