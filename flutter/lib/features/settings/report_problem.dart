// Settings > Report a problem: what happened in the player's words, with the diagnostics folded in (the
// build, the phone, what was up, the last crash, the frames that stuttered, the last events and the log),
// copied to the clipboard or handed to the mail app. It goes only when the player sends it, and it carries
// no health data (the log has game events and errors, never steps).

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/diagnostics.dart';
import '../shared/widgets.dart';

/// Where reports go (site/config.json's supportEmail; set at build time with --dart-define=SUPPORT_EMAIL=...).
const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@evochigame.com');

class DiagnosticsReport {
  DiagnosticsReport._();

  static String text(GameController c, {String what = ''}) {
    final s = c.state;
    final pet = s.pet;
    final st = s.player?.settings;
    final b = StringBuffer();
    b.writeln('Evochi problem report');
    b.writeln('build: ${c.config.version} (${Diagnostics.build})');
    b.writeln('phone: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    b.writeln('when: ${DateTime.now().toIso8601String()}');
    b.writeln('screen: ${Diagnostics.screen}');
    if (pet != null) b.writeln('evochi: stage ${pet.stage} ${pet.paletteId} level ${c.view.pet?.level.level ?? '?'}');
    if (st != null) b.writeln('settings: reduce motion ${st.reducedMotion}, short ultimates ${st.shortUltimates}, large text ${st.largeText}');
    b.writeln('storage: ${c.repo.storageOk ? 'ok' : 'unavailable'}');
    if (what.trim().isNotEmpty) {
      b.writeln();
      b.writeln('what happened:');
      b.writeln(what.trim());
    }
    if (!Diagnostics.lastSessionClean) {
      b.writeln();
      b.writeln('the last session did not end cleanly${Diagnostics.lastSessionAt == null ? '' : ' (${Diagnostics.lastSessionAt!.toIso8601String()})'}: its last lines');
      final last = Diagnostics.lastSessionLog ?? '';
      b.writeln(last.length > 3000 ? last.substring(last.length - 3000) : last);
    }
    final jank = JankWatch.summary();
    if (jank.isNotEmpty) {
      b.writeln();
      b.writeln('frames: $jank');
    }
    final crashes = Diagnostics.local.records;
    if (crashes.isNotEmpty) {
      b.writeln();
      b.writeln('errors recorded (${crashes.length}):');
      for (final r in crashes.reversed.take(3)) {
        b.writeln('- ${r.t.toIso8601String()} ${r.fatal ? 'FATAL' : 'error'} on ${r.screen}: ${r.error}');
        final lines = r.stack.split('\n').where((l) => l.trim().isNotEmpty).take(12);
        for (final l in lines) {
          b.writeln('    $l');
        }
      }
    }
    b.writeln();
    b.writeln('log (newest last):');
    b.writeln(Log.tail(250));
    return b.toString();
  }
}

/// The sheet: a line about what happened, then copy or email.
Future<void> showReportProblem(BuildContext context) => showEvochiSheet<void>(context, builder: (s) => const _ReportSheet());

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _what = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _what.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final c = context.read<GameController>();
    await Clipboard.setData(ClipboardData(text: DiagnosticsReport.text(c, what: _what.text)));
    if (!mounted) return;
    c.toast('The report was copied: paste it in a message to us', icon: 'lock');
    Navigator.pop(context);
  }

  Future<void> _email() async {
    final c = context.read<GameController>();
    setState(() => _busy = true);
    final report = DiagnosticsReport.text(c, what: _what.text);
    // the whole report on the clipboard (mail apps cut a long body short), a summary in the mail itself
    await Clipboard.setData(ClipboardData(text: report));
    final summary = report.length > 1500 ? '${report.substring(0, 1500)}\n…\n(the full report is on your clipboard: paste it here)' : report;
    final uri = Uri.parse('mailto:$supportEmail?subject=${Uri.encodeComponent('Evochi problem report (${Diagnostics.build})')}&body=${Uri.encodeComponent(summary)}');
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    c.toast(opened ? 'The full report is on your clipboard too: paste it into the mail' : 'No mail app: the report was copied, send it to $supportEmail', icon: 'lock');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final crashed = !Diagnostics.lastSessionClean || Diagnostics.local.records.any((r) => r.fatal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Report a problem', style: EvochiText.section),
      const SizedBox(height: 6),
      Text(
        crashed
            ? 'Evochi stopped unexpectedly last time. Tell us what you were doing: the report carries the last things it did, so we can find the cause.'
            : 'Tell us what went wrong. The report carries the build, your phone\'s system version, the screen you were on and the last things the game did. Never your steps.',
        style: EvochiText.bodyText,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _what,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'What happened?', hintText: 'e.g. the Wilds froze when my Elder used Tremor', filled: true, fillColor: EvochiColor.shell),
      ),
      const SizedBox(height: 12),
      EvochiButton(label: 'Email the report', busy: _busy, onPressed: _email),
      const SizedBox(height: 8),
      EvochiButton(label: 'Copy the report', tone: ButtonTone.cream, onPressed: _copy),
    ]);
  }
}
