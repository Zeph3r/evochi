// Day attribution in the account time zone (style guide §14-15, QA Q11).
// A day key is "YYYY-MM-DD" in the player's saved IANA zone - never the
// device's current zone - so travelling can't double-count a day.

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const int hourMs = 3600000;
const int dayMs = 86400000;

bool _tzReady = false;

void ensureTimeZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

tz.Location _loc(String zone) {
  ensureTimeZones();
  try {
    return tz.getLocation(zone);
  } catch (_) {
    return tz.UTC;
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatKey(int y, int m, int d) => '${y.toString().padLeft(4, '0')}-${_two(m)}-${_two(d)}';

String dayKey(int ms, String zone) {
  final t = tz.TZDateTime.fromMillisecondsSinceEpoch(_loc(zone), ms);
  return formatKey(t.year, t.month, t.day);
}

List<int> _parts(String key) => key.split('-').map(int.parse).toList();

/// UTC instant (ms) of local midnight that starts [key] in [zone].
int dayStart(String key, String zone) {
  final p = _parts(key);
  return tz.TZDateTime(_loc(zone), p[0], p[1], p[2]).millisecondsSinceEpoch;
}

int dayEnd(String key, String zone) => dayStart(addDays(key, 1), zone);

String addDays(String key, int n) {
  final p = _parts(key);
  final d = DateTime.utc(p[0], p[1], p[2] + n);
  return formatKey(d.year, d.month, d.day);
}

/// b - a in whole calendar days.
int diffDays(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  return DateTime.utc(pb[0], pb[1], pb[2]).difference(DateTime.utc(pa[0], pa[1], pa[2])).inDays;
}

/// ISO-8601 week key (Monday start), e.g. "2026-W41".
String weekKey(String key) {
  final p = _parts(key);
  final dt = DateTime.utc(p[0], p[1], p[2]);
  final dow = (dt.weekday + 6) % 7; // Mon = 0
  final thursday = dt.add(Duration(days: 3 - dow));
  final wy = thursday.year;
  final jan4 = DateTime.utc(wy, 1, 4);
  final jan4dow = (jan4.weekday + 6) % 7;
  final week1Monday = jan4.subtract(Duration(days: jan4dow));
  final week = 1 + thursday.difference(week1Monday).inDays ~/ 7;
  return '$wy-W${_two(week)}';
}

List<String> weekDays(String key) {
  final p = _parts(key);
  final dt = DateTime.utc(p[0], p[1], p[2]);
  final dow = (dt.weekday + 6) % 7;
  final monday = addDays(key, -dow);
  return List.generate(7, (i) => addDays(monday, i));
}

int hourIn(int ms, String zone) => tz.TZDateTime.fromMillisecondsSinceEpoch(_loc(zone), ms).hour;
