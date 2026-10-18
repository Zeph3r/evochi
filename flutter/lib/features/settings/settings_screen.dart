// S13 Profile / Settings: account, goal, step source, reminders, accessibility, privacy, playtest tools.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../../data/health_adapters/step_source.dart';
import '../../game/engine.dart' as g;
import '../shared/widgets.dart';

const _zones = [
  'UTC', 'America/Los_Angeles', 'America/Denver', 'America/Chicago', 'America/New_York', 'America/Sao_Paulo', 'Europe/London',
  'Europe/Berlin', 'Africa/Lagos', 'Asia/Kolkata', 'Asia/Singapore', 'Asia/Tokyo', 'Australia/Sydney',
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final pl = s.player!;
    final st = pl.settings;
    final conn = s.steps.connection;
    final zones = {pl.timezone, s.tzHint, ..._zones}.toList();
    final offDays = (s.clockOffset / dayMs).round();

    Widget toggle(String title, String? desc, bool value, void Function(Settings, bool) set) => SwitchListTile(
          value: value,
          onChanged: (v) => c.updateSettings((x) => set(x, v)),
          title: Text(title, style: EvochiText.cardTitle.copyWith(fontSize: 15)),
          subtitle: desc == null ? null : Text(desc, style: EvochiText.caption),
          activeTrackColor: EvochiColor.steps,
        );

    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(art.thumb('forest'), fit: BoxFit.cover),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(0, 0.2), end: Alignment.bottomCenter, colors: [Color(0x00F8EBDD), EvochiColor.panel]))),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    BackSquareButton(onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 10),
                    const TitleImage('title_profile', height: 40, label: 'Profile and settings'),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 24 + MediaQuery.of(context).padding.bottom),
          sliver: SliverList.list(children: [
            GameCard(
              child: Row(children: [
                const VoxelIcon('paw', size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(pl.accountType == 'guest' ? 'Guest player' : (pl.email ?? 'Account'), style: EvochiText.cardTitle),
                      // Village Tales title (Chapter 1 finale)
                      if (c.state.story.titleUnlocks.contains('first_lightkeeper')) const Tag('First Lightkeeper', tone: TagTone.stage, icon: 'crown'),
                    ]),
                    Text(
                      pl.accountType == 'guest' ? 'Saved on this device only. Link an account so your Evochi can move to a new phone.' : 'Signed in. Progress syncs when the cloud backend is configured.',
                      style: EvochiText.caption,
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(children: [
                const Row(children: [
                  VoxelIcon('star', size: 32),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Daily step goal', style: EvochiText.cardTitle),
                      Text('A game target, not a health prescription. Changes apply from today.', style: EvochiText.caption),
                    ]),
                  ),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(tooltip: 'Decrease goal', onPressed: () => c.run((x, n) => g.setGoal(x, (pl.goal - 500).clamp(c.config.goalMin, c.config.goalMax), n)), icon: const Icon(Icons.remove_circle_outline)),
                  SizedBox(width: 110, child: Text(fmt(pl.goal), textAlign: TextAlign.center, style: EvochiText.number.copyWith(fontSize: 28))),
                  IconButton(tooltip: 'Increase goal', onPressed: () => c.run((x, n) => g.setGoal(x, (pl.goal + 500).clamp(c.config.goalMin, c.config.goalMax), n)), icon: const Icon(Icons.add_circle_outline)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const VoxelIcon('steps', size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Step source', style: EvochiText.cardTitle),
                      Text(
                        switch (conn) {
                          'health' => c.health.displayName,
                          'demo' => 'Simulated step device',
                          'manual' => 'Manual entry (unverified)',
                          _ => 'Not connected',
                        },
                        style: EvochiText.caption,
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  EvochiButton(
                    label: c.health.displayName,
                    small: true,
                    expand: false,
                    tone: conn == 'health' ? ButtonTone.green : ButtonTone.cream,
                    onPressed: () async {
                      final p = await c.connectHealth();
                      if (p != StepPermission.granted) {
                        c.toast(p == StepPermission.unavailable ? 'Step data is not available on this device' : 'Permission not granted - you can try again any time', icon: 'steps', kind: 'warn');
                      }
                    },
                  ),
                  EvochiButton(label: 'Simulated', small: true, expand: false, tone: conn == 'demo' ? ButtonTone.green : ButtonTone.cream, onPressed: () => c.run((x, n) => g.setConnection(x, 'demo', n))),
                  EvochiButton(label: 'Manual', small: true, expand: false, tone: conn == 'manual' ? ButtonTone.green : ButtonTone.cream, onPressed: () => c.run((x, n) => g.setConnection(x, 'manual', n))),
                  EvochiButton(label: 'Disconnect', small: true, expand: false, tone: ButtonTone.cream, onPressed: conn == 'none' ? null : () => c.run((x, n) => g.setConnection(x, 'none', n))),
                ]),
                const SizedBox(height: 6),
                const Text('Evochi reads only daily step counts. Missing data is shown as "sync pending", never as inactivity.', style: EvochiText.caption),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                toggle('Daily reminder', "One gentle nudge if you haven't visited, outside quiet hours. Never about your health.", st.notifications, (x, v) => x.notifications = v),
                if (st.notifications)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(children: [
                      const Text('Quiet hours', style: EvochiText.bodyText),
                      const Spacer(),
                      DropdownButton<int>(
                        value: st.quietStart,
                        items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                        onChanged: (v) => c.updateSettings((x) => x.quietStart = v ?? x.quietStart),
                      ),
                      const Text(' to '),
                      DropdownButton<int>(
                        value: st.quietEnd,
                        items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                        onChanged: (v) => c.updateSettings((x) => x.quietEnd = v ?? x.quietEnd),
                      ),
                    ]),
                  ),
                toggle('Sound effects', null, st.sound, (x, v) => x.sound = v),
                toggle('Ambient music', null, st.music, (x, v) => x.music = v),
                toggle('Haptics', null, st.haptics, (x, v) => x.haptics = v),
                toggle('Reduce motion', 'Crossfades instead of bounces, flashes and particles.', st.reducedMotion, (x, v) => x.reducedMotion = v),
                toggle('Classic villagers', "Flat, evenly lit villagers instead of ones lit by each room's lanterns and windows.", st.classicVillagers,
                    (x, v) => x.classicVillagers = v),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Account time zone', style: EvochiText.cardTitle),
                const Text("Decides when your day starts. Travelling doesn't change it unless you do.", style: EvochiText.caption),
                DropdownButton<String>(
                  isExpanded: true,
                  value: pl.timezone,
                  items: [for (final z in zones) DropdownMenuItem(value: z, child: Text(z))],
                  onChanged: (z) {
                    if (z == null) return;
                    c.run((x, n) => g.setTimezone(x, z));
                    c.toast('Day boundaries now follow $z', icon: 'pin');
                  },
                ),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [
                  VoxelIcon('lock', size: 30),
                  SizedBox(width: 10),
                  Expanded(child: Text('Privacy & data', style: EvochiText.cardTitle)),
                ]),
                const Text('Evochi stores daily step totals and game progress - never raw health telemetry.', style: EvochiText.caption),
                toggle('Share anonymous usage events', 'Product events only, no health data.', st.analytics, (x, v) => x.analytics = v),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  EvochiButton(
                    label: 'Export my data',
                    small: true,
                    expand: false,
                    tone: ButtonTone.cream,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(s.toJson())));
                      c.toast('Your data was copied to the clipboard', icon: 'lock');
                    },
                  ),
                  EvochiButton(
                    label: 'Delete all data',
                    small: true,
                    expand: false,
                    tone: ButtonTone.danger,
                    onPressed: () => showEvochiDialog<void>(context, builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Delete everything?', style: EvochiText.section),
                          const SizedBox(height: 8),
                          const Text("This removes your Evochi, coins, items and step history. It can't be undone.", style: EvochiText.bodyText),
                          const SizedBox(height: 12),
                          EvochiButton(
                            label: 'Delete all data',
                            tone: ButtonTone.danger,
                            onPressed: () async {
                              Navigator.pop(d);
                              Navigator.of(context).popUntil((r) => r.isFirst);
                              await c.deleteAllData();
                            },
                          ),
                          const SizedBox(height: 8),
                          EvochiButton(label: 'Cancel', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
                        ])),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              color: const Color(0xD9FFF9F0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Playtest tools', style: EvochiText.cardTitle),
                Text('Shortcuts for testing progression. Clock offset: +$offDays day${offDays == 1 ? '' : 's'}.', style: EvochiText.caption),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  EvochiButton(label: '+500 coins', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => c.run((x, n) => g.grantCoins(x, 500, n))),
                  EvochiButton(label: 'Walk 1 goal day', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => c.advanceDays(1, 1.05)),
                  EvochiButton(label: 'Walk 7 goal days', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => c.advanceDays(7, 1.05)),
                  EvochiButton(label: 'Fast-track evolution', small: true, expand: false, tone: ButtonTone.cream, onPressed: c.fastTrackEvolution),
                  EvochiButton(label: 'Skip 3 idle days', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => c.advanceDays(3, 0)),
                  EvochiButton(label: '+3 Healing Herbs', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => c.grantHerbs(3)),
                ]),
                const SizedBox(height: 12),
                const Text('Home Tales', style: EvochiText.cardTitle),
                const Text('Garden, Cottage, Kitchen, Apothecary and Skills.', style: EvochiText.caption),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  EvochiButton(
                    label: 'Skip 1 hour',
                    small: true,
                    expand: false,
                    tone: ButtonTone.cream,
                    onPressed: () {
                      c.skipTime(hourMs);
                      c.toast('An hour passed (no steps)', icon: 'skill_farming');
                    },
                  ),
                  EvochiButton(
                    label: 'Skip to Home Tales',
                    small: true,
                    expand: false,
                    tone: ButtonTone.cream,
                    onPressed: () {
                      final changed = c.homeTalesReady();
                      c.toast(changed ? 'Chapter 1 quest 1 done and level 2 reached: Bram has a job for you' : 'Home Tales are already open', icon: 'home_map');
                    },
                  ),
                  EvochiButton(
                    label: '+ Seeds and ingredients',
                    small: true,
                    expand: false,
                    tone: ButtonTone.cream,
                    onPressed: () {
                      c.grantPantry();
                      c.toast('Seeds and ingredients added to Bag > Pantry', icon: 'skill_farming');
                    },
                  ),
                  EvochiButton(
                    label: '+1 level, every skill',
                    small: true,
                    expand: false,
                    tone: ButtonTone.cream,
                    onPressed: () {
                      c.skillsUp();
                      c.toast('Every skill went up a level', icon: 'star');
                    },
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Evochi ${c.config.version} - ${c.repo.storageOk ? 'saved on this device' : 'storage unavailable, progress kept in memory'}',
                textAlign: TextAlign.center, style: EvochiText.caption),
          ]),
        ),
      ]),
    );
  }
}
