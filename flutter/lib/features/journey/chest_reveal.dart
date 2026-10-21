// The Daily Chest opening (economy plan, "Daily Chest"): the chest drops onto the screen, wobbles in its
// tier's glow, opens on a tap (three for Gold and Lumen, each shaking harder), bursts with light, and
// deals its rewards out one card at a time. A rare find gets a beat of slow motion and a sparkle.
// "Collect" sends the cards up toward the satchel and closes.
//
// The rewards are already in the save when this plays (claimQuest grants them); this is only the
// show. Reduced motion skips straight to the open chest and the cards, face up.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/haptics.dart';
import '../shared/widgets.dart';

/// Plays the chest opening over the current screen. [tier] is wood | silver | gold | lumen (anything else
/// shows as wood); [rewards] are the claim's reward maps ({'kind': 'coins' | 'glimmer', 'amount': n} or
/// {'kind': 'item', 'itemId': id}). Coins and Glimmer are summed into one card each; repeated items stack.
Future<void> showChestReveal(BuildContext context, {required String tier, required List<Map<String, Object?>> rewards}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, a, b) => ChestReveal(tier: tier, rewards: rewards),
      transitionsBuilder: (ctx, a, b, child) => FadeTransition(opacity: a, child: child),
    ));

/// "Wooden chest", "Silver chest", "Gold chest", "Lumen chest".
String chestTierLabel(String tier) => _lookOf(tier).label;

// ------------------------------------------------------------------ the tiers
class _TierLook {
  const _TierLook(this.label, this.glow, this.deep, this.taps);
  final String label;
  final Color glow; // the halo, rays and sparks
  final Color deep; // the card backs
  final int taps; // taps to open
}

const _tiers = <String, _TierLook>{
  'wood': _TierLook('Wooden chest', Color(0xFFE6AE6E), Color(0xFF8A5A36), 1),
  'silver': _TierLook('Silver chest', Color(0xFFE2EAF1), Color(0xFF7F8D9A), 1),
  'gold': _TierLook('Gold chest', Color(0xFFFFD66B), Color(0xFFC98A2C), 3),
  'lumen': _TierLook('Lumen chest', Color(0xFF8FF3EC), Color(0xFF3B8FA6), 3),
};

_TierLook _lookOf(String tier) => _tiers[tier] ?? _tiers['wood']!;

const _rarityColor = <String, Color>{
  'common': Color(0xFFC9A78C),
  'uncommon': Color(0xFF82B75E),
  'rare': Color(0xFF399CC7),
  'epic': Color(0xFFAA8BCF),
  'legendary': Color(0xFFF4B84E),
};
const _rarityRank = {'common': 0, 'uncommon': 1, 'rare': 2, 'epic': 3, 'legendary': 4};
const _glimmerColor = Color(0xFF7FD8E8);
const _coinColor = Color(0xFFF4B84E);

Color _a(Color c, double alpha) => c.withAlpha((alpha.clamp(0.0, 1.0) * 255).round());

// ------------------------------------------------------------------ the cards
class _Card {
  _Card(this.kind, {this.amount = 0, this.itemId});
  final String kind; // coins | glimmer | item
  final int amount; // coins/glimmer: the sum; items: how many
  final String? itemId;

  String get rarity => switch (kind) {
        'item' => catalog[itemId]?.rarity ?? 'common',
        'glimmer' => 'rare',
        _ => 'common',
      };

  /// Rare finds (and Glimmer) get the slow-motion beat.
  bool get special => (_rarityRank[rarity] ?? 0) >= 2;

  Color get color => switch (kind) {
        'coins' => _coinColor,
        'glimmer' => _glimmerColor,
        _ => _rarityColor[rarity] ?? _rarityColor['common']!,
      };

  String get title => switch (kind) {
        'coins' || 'glimmer' => '+$amount',
        _ => '${catalog[itemId]?.name ?? itemId}${amount > 1 ? ' ×$amount' : ''}',
      };

  String get sub => switch (kind) {
        'coins' => 'EvoCoins',
        'glimmer' => 'Glimmer',
        _ => '${rarity[0].toUpperCase()}${rarity.substring(1)}',
      };

  String get spoken => switch (kind) {
        'coins' => '$amount EvoCoins',
        'glimmer' => '$amount Glimmer',
        _ => title,
      };
}

/// Coins first, then the everyday finds, then Glimmer, then the rare finds (the best for last).
List<_Card> _cardsFor(List<Map<String, Object?>> rewards) {
  var coins = 0, glimmer = 0;
  final items = <String, int>{};
  for (final r in rewards) {
    final amt = (r['amount'] as num?)?.toInt() ?? 0;
    switch (r['kind']) {
      case 'coins':
        coins += amt;
      case 'glimmer':
        glimmer += amt;
      case 'item':
        final id = r['itemId'];
        if (id is String) items[id] = (items[id] ?? 0) + 1;
    }
  }
  final ids = items.keys.toList()..sort((a, b) => (_rarityRank[catalog[a]?.rarity] ?? 0).compareTo(_rarityRank[catalog[b]?.rarity] ?? 0));
  final plain = [for (final id in ids) if ((_rarityRank[catalog[id]?.rarity] ?? 0) < 2) _Card('item', amount: items[id]!, itemId: id)];
  final rare = [for (final id in ids) if ((_rarityRank[catalog[id]?.rarity] ?? 0) >= 2) _Card('item', amount: items[id]!, itemId: id)];
  return [
    if (coins > 0) _Card('coins', amount: coins),
    ...plain,
    if (glimmer > 0) _Card('glimmer', amount: glimmer),
    ...rare,
  ];
}

// ------------------------------------------------------------------ images (never throw)
String? _safe(String Function() f) {
  try {
    return f();
  } catch (_) {
    return null; // a key missing from the art manifest (new art not packed yet)
  }
}

Widget _iconImg(String name, double size, {String fallback = 'star'}) {
  final p = _safe(() => art.icon(name)) ?? _safe(() => art.icon(fallback));
  if (p == null) return SizedBox(width: size, height: size);
  return Image.asset(p,
      width: size, height: size, filterQuality: FilterQuality.medium, excludeFromSemantics: true, errorBuilder: (_, __, ___) => SizedBox(width: size, height: size));
}

Widget _itemImg(String id, double size) {
  final p = _safe(() => art.item(id));
  if (p == null) return _iconImg('star', size);
  return Image.asset(p,
      width: size, height: size, filterQuality: FilterQuality.medium, excludeFromSemantics: true, errorBuilder: (_, __, ___) => _iconImg('star', size));
}

String _chestPath(String tier, bool open) => 'assets/art/economy/chest_${_tiers.containsKey(tier) ? tier : 'wood'}_${open ? 'open' : 'closed'}.webp';

// ------------------------------------------------------------------ particles
class _Particle {
  _Particle(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color, this.kind, {this.drag = 0, this.gravity = 0});
  double x, y, vx, vy;
  double age = 0;
  final double life, size;
  final Color color;
  final int kind; // 0 dust (grows and fades), 1 spark, 2 star
  final double drag, gravity;
}

enum _Phase { drop, idle, shake, burst, reveal, done, collect }

const _dropDur = 0.62;
const _landAt = _dropDur * 0.364; // bounceOut's first contact
const _collectDur = 0.5;

class ChestReveal extends StatefulWidget {
  const ChestReveal({super.key, required this.tier, required this.rewards});
  final String tier;
  final List<Map<String, Object?>> rewards;
  @override
  State<ChestReveal> createState() => _ChestRevealState();
}

class _ChestRevealState extends State<ChestReveal> with SingleTickerProviderStateMixin {
  late final List<_Card> _cards = _cardsFor(widget.rewards);
  late final _TierLook _look = _lookOf(widget.tier);
  Ticker? _ticker; // only when animating (reduced motion never builds one)
  final _rng = math.Random();
  final _parts = <_Particle>[];
  GameController? _c;

  Duration _last = Duration.zero;
  double _clock = 0; // since the overlay opened
  double _pt = 0; // since the phase began
  _Phase _phase = _Phase.drop;
  int _taps = 0;
  bool _landed = false;
  bool _open = false;
  bool _closing = false;
  bool _reduced = false;
  bool _ready = false;
  double _openedAt = 0;
  double _shakeDur = 0.3;
  double _shakeAmp = 0;
  double _flash = 0;
  double _pop = 0;
  List<double> _starts = const [];
  List<double> _durs = const [];
  final _flipped = <int>{};
  double _revealEnd = 0;
  Size _size = Size.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    try {
      _c = context.read<GameController>();
    } catch (_) {
      _c = null; // no controller above (a test harness): silent
    }
    for (final open in [false, true]) {
      precacheImage(AssetImage(_chestPath(widget.tier, open)), context, onError: (_, __) {});
    }
    _reduced = MediaQuery.of(context).disableAnimations;
    if (_reduced) {
      _open = true;
      _landed = true;
      _phase = _Phase.done;
      _flipped.addAll(List.generate(_cards.length, (i) => i));
      _sfx('reward_chime', 0.7);
    } else {
      _ticker = createTicker(_tick)..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  // ---- sound and feel (both quiet when the player turned them off)
  void _sfx(String name, [double v = 0.8]) => _c?.audio.play(name, volume: v);
  void _buzz(Haptic h, [double s = 1]) => _c?.audio.buzz(h, strength: s);

  // ---- geometry
  double get _chestSize => math.min(280.0, math.min(_size.width * 0.62, _size.height * 0.34));
  Offset get _chestC => Offset(_size.width / 2, _size.height * 0.4);
  Offset get _mouth => _chestC - Offset(0, _chestSize * 0.12);
  int get _perRow => _cards.length <= 4 ? math.max(1, _cards.length) : 3;

  Size get _cardSize {
    final n = _perRow;
    final w = math.min(108.0, (_size.width - 32 - (n - 1) * 12) / n);
    return Size(w, w * 1.24);
  }

  Offset _slot(int i) {
    final per = _perRow;
    final row = i ~/ per, col = i % per;
    final inRow = math.min(per, _cards.length - row * per);
    final cs = _cardSize;
    const gap = 12.0;
    final rowW = inRow * cs.width + (inRow - 1) * gap;
    final x = (_size.width - rowW) / 2 + col * (cs.width + gap) + cs.width / 2;
    final y = _chestC.dy + _chestSize * 0.5 + 22 + cs.height / 2 + row * (cs.height + gap);
    return Offset(x, y);
  }

  // ---- the clock
  void _go(_Phase p) {
    _phase = p;
    _pt = 0;
  }

  void _tick(Duration el) {
    final dt = ((el - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = el;
    _clock += dt;
    _pt += dt;
    _flash = math.max(0, _flash - dt * 2.4);
    _pop = math.max(0, _pop - dt * 3.0);
    for (final p in _parts) {
      p.age += dt;
      final k = math.max(0.0, 1 - p.drag * dt);
      p.vx *= k;
      p.vy = p.vy * k + p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    _parts.removeWhere((p) => p.age >= p.life);
    switch (_phase) {
      case _Phase.drop:
        if (!_landed && _pt >= _landAt) {
          _landed = true;
          _land();
        }
        if (_pt >= _dropDur) _go(_Phase.idle);
      case _Phase.shake:
        if (_pt >= _shakeDur) {
          if (_taps >= _look.taps) {
            _burst();
          } else {
            _go(_Phase.idle);
          }
        }
      case _Phase.burst:
        if (_pt >= 0.42) _startReveal();
      case _Phase.reveal:
        for (var i = 0; i < _cards.length; i++) {
          if (!_flipped.contains(i) && _pt >= _starts[i] + _durs[i]) {
            _flipped.add(i);
            _onFlip(i);
          }
        }
        if (_pt >= _revealEnd) _go(_Phase.done);
      case _Phase.collect:
        if (_pt >= _collectDur && !_closing) {
          _closing = true;
          Navigator.of(context).pop();
        }
      case _Phase.idle:
      case _Phase.done:
        break;
    }
    if (mounted) setState(() {});
  }

  // ---- beats
  void _land() {
    final y = _chestC.dy + _chestSize * 0.4;
    for (var i = 0; i < 16; i++) {
      final side = i.isEven ? 1.0 : -1.0;
      _parts.add(_Particle(
        _chestC.dx + side * _chestSize * (0.15 + _rng.nextDouble() * 0.3),
        y + _rng.nextDouble() * 6,
        side * (60 + _rng.nextDouble() * 140),
        -20 - _rng.nextDouble() * 50,
        0.55 + _rng.nextDouble() * 0.35,
        6 + _rng.nextDouble() * 8,
        const Color(0xFFD9C7B0),
        0,
        drag: 3.2,
      ));
    }
    _sfx('wild_crash', 0.22);
    _buzz(Haptic.thump, 0.55);
  }

  void _sparks(Offset at, int n, Color col, {double speed = 220, double gravity = 380, double life = 0.7}) {
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rng.nextDouble() - 0.5) * math.pi * 1.5;
      final v = speed * (0.45 + _rng.nextDouble() * 0.75);
      _parts.add(_Particle(at.dx, at.dy, math.cos(a) * v, math.sin(a) * v, life * (0.6 + _rng.nextDouble() * 0.6), 2.5 + _rng.nextDouble() * 3.0,
          _rng.nextDouble() < 0.3 ? Colors.white : col, 1,
          drag: 1.2, gravity: gravity));
    }
  }

  void _stars(Offset at, int n, Color col, {double spread = 60}) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = 30 + _rng.nextDouble() * 90;
      _parts.add(_Particle(at.dx + math.cos(a) * spread * 0.3, at.dy + math.sin(a) * spread * 0.3, math.cos(a) * v, math.sin(a) * v - 20,
          0.7 + _rng.nextDouble() * 0.5, 5 + _rng.nextDouble() * 6, _rng.nextBool() ? Colors.white : col, 2,
          drag: 2.0));
    }
  }

  void _tapChest() {
    if (_phase == _Phase.drop && !_landed) return;
    if (_phase == _Phase.shake && _pt < _shakeDur * 0.45) return; // let the last shake read
    if (_phase != _Phase.idle && _phase != _Phase.drop && _phase != _Phase.shake) return;
    _taps = math.min(_look.taps, _taps + 1);
    final k = _taps / _look.taps;
    final last = _taps >= _look.taps;
    _shakeAmp = 0.35 + 0.65 * k;
    _shakeDur = _look.taps == 1 ? 0.26 : 0.34;
    _buzz(last ? Haptic.thump : (_taps == 1 ? Haptic.tap : Haptic.hit), 0.45 + 0.55 * k);
    _sfx('ui_tap', 0.35 + 0.35 * k);
    _sparks(_mouth, 4 + (10 * k).round(), _look.glow, speed: 150 + 90 * k, life: 0.5);
    _go(_Phase.shake);
  }

  void _burst() {
    _open = true;
    _openedAt = _clock;
    _flash = 1;
    _pop = 1;
    _go(_Phase.burst);
    _sparks(_mouth, 42, _look.glow, speed: 360, gravity: 440, life: 0.9);
    _stars(_mouth, 10, _look.glow, spread: _chestSize * 0.5);
    _sfx('reward_chime', 0.85);
    _buzz(Haptic.reward);
  }

  void _startReveal() {
    if (_cards.isEmpty) {
      _go(_Phase.done);
      return;
    }
    final starts = <double>[], durs = <double>[];
    var t = 0.0;
    var end = 0.0;
    for (final c in _cards) {
      final d = c.special ? 0.62 : 0.42; // a rare find travels slower
      starts.add(t);
      durs.add(d);
      end = math.max(end, t + d + (c.special ? 0.5 : 0.12));
      t += c.special ? d + 0.5 : 0.24;
    }
    _starts = starts;
    _durs = durs;
    _revealEnd = end;
    _go(_Phase.reveal);
  }

  void _onFlip(int i) {
    final c = _cards[i];
    final at = _slot(i);
    if (c.special) {
      _stars(at, 16, c.color, spread: _cardSize.width);
      _sparks(at, 18, c.color, speed: 200, gravity: 260, life: 0.6);
      _sfx('level_up', 0.7);
    } else {
      _sparks(at, 6, c.color, speed: 120, gravity: 300, life: 0.4);
      _sfx('coin', 0.3);
    }
  }

  void _skip() {
    if (_phase != _Phase.burst && _phase != _Phase.reveal) return;
    _open = true;
    final unseen = [for (var i = 0; i < _cards.length; i++) if (!_flipped.contains(i)) i];
    _flipped.addAll(unseen);
    if (unseen.any((i) => _cards[i].special)) _sfx('level_up', 0.6);
    _go(_Phase.done);
  }

  void _collect() {
    if (_phase == _Phase.collect || _closing) return;
    _sfx('coin', 0.6);
    if (_reduced) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    _go(_Phase.collect);
  }

  void _onBackgroundTap() {
    if (_phase == _Phase.reveal || _phase == _Phase.burst) {
      _skip();
    } else {
      _tapChest();
    }
  }

  // ---- drawing
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        final collectK = _phase == _Phase.collect ? Curves.easeIn.transform((_pt / _collectDur).clamp(0.0, 1.0)) : 0.0;
        final opened = _open ? (_reduced ? 1.0 : ((_clock - _openedAt) * 3).clamp(0.0, 1.0)) : 0.0;
        final glow = switch (_phase) {
          _Phase.drop => _landed ? 0.35 : 0.0,
          _Phase.idle => 0.36 + 0.18 * math.sin(_clock * 4),
          _Phase.shake => 0.5 + 0.4 * _shakeAmp,
          _ => 0.72,
        };
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onBackgroundTap,
          child: Stack(children: [
            // the scrim
            Positioned.fill(child: Container(color: const Color(0xD9140F0C))),
            // halo and rays behind the chest
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BackPainter(
                    center: _chestC,
                    chestSize: _chestSize,
                    color: _look.glow,
                    glow: glow * (1 - collectK),
                    rays: opened * 0.6 * (1 - collectK),
                    rot: _clock * 0.22,
                  ),
                ),
              ),
            ),
            _chest(collectK),
            // dust, sparks and stars
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FxPainter(_parts)))),
            for (var i = 0; i < _cards.length; i++) _cardAt(i),
            // the white pop as the lid bursts
            if (_flash > 0) Positioned.fill(child: IgnorePointer(child: Container(color: _a(Colors.white, _flash * 0.35)))),
            Positioned(left: 16, right: 16, top: mq.padding.top + 28, child: IgnorePointer(child: _header())),
            Positioned(left: 16, right: 16, bottom: mq.padding.bottom + 24, child: _footer()),
            Semantics(
              liveRegion: true,
              label: _phase == _Phase.done ? '${_look.label} opened: ${_cards.map((c) => c.spoken).join(', ')}' : null,
              child: const SizedBox.shrink(),
            ),
          ]),
        );
      }),
    );
  }

  Widget _chest(double collectK) {
    final s = _chestSize;
    var dx = 0.0, dy = 0.0, rot = 0.0, sx = 1.0, sy = 1.0;
    switch (_phase) {
      case _Phase.drop:
        final t = (_pt / _dropDur).clamp(0.0, 1.0);
        dy = -(_size.height * 0.62) * (1 - Curves.bounceOut.transform(t));
        if (_landed) {
          final q = math.max(0.0, 1 - (_pt - _landAt) / 0.2);
          sx = 1 + 0.09 * q;
          sy = 1 - 0.09 * q;
        }
      case _Phase.idle:
        rot = math.sin(_clock * 3.1) * 0.03;
        dy = math.sin(_clock * 2.2) * 3;
      case _Phase.shake:
        final d = (_pt / _shakeDur).clamp(0.0, 1.0);
        final amp = _shakeAmp * (1 - d);
        rot = math.sin(_pt * 55) * 0.13 * amp;
        dx = math.sin(_pt * 47) * 9 * amp;
        sy = 1 - 0.05 * amp;
        sx = 1 + 0.03 * amp;
      case _Phase.burst:
      case _Phase.reveal:
      case _Phase.done:
      case _Phase.collect:
        rot = math.sin(_clock * 2.0) * 0.008;
    }
    final pop = 1 + 0.12 * _pop;
    return Positioned(
      left: _chestC.dx - s / 2 + dx,
      top: _chestC.dy - s / 2 + dy,
      width: s,
      height: s,
      child: Semantics(
        button: !_open,
        label: _open ? _look.label : 'Open the ${_look.label.toLowerCase()}',
        onTap: _open ? null : _tapChest,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tapChest,
          child: Opacity(
            opacity: 1 - collectK,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..rotateZ(rot)
                ..scale(sx * pop, sy * pop),
              child: _chestImage(_open, s),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chestImage(bool open, double s) => Image.asset(
        _chestPath(widget.tier, open),
        width: s,
        height: s,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => _fallbackChest(open, s),
      );

  /// Before the tier art is packed: the chest icon, tinted to the tier (brighter once open).
  Widget _fallbackChest(bool open, double s) => Center(
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(_a(_look.glow, open ? 0.6 : 0.4), BlendMode.srcATop),
          child: _iconImg('chest', s * (open ? 0.86 : 0.8)),
        ),
      );

  Widget _cardAt(int i) {
    final cs = _cardSize;
    final slot = _slot(i);
    final c = _cards[i];
    var pos = slot;
    var scale = 1.0, angle = 0.0, tilt = 0.0, opacity = 1.0;
    switch (_phase) {
      case _Phase.reveal:
        final local = (_pt - _starts[i]) / _durs[i];
        if (local <= 0) return const SizedBox.shrink();
        final fly = Curves.easeOutCubic.transform((local / 0.7).clamp(0.0, 1.0));
        final ctrl = Offset((_mouth.dx + slot.dx) / 2, math.min(_mouth.dy, slot.dy) - _chestSize * 0.55);
        pos = _bezier(_mouth, ctrl, slot, fly);
        scale = 0.3 + 0.7 * fly;
        tilt = (1 - fly) * 0.6 * (i.isEven ? -1 : 1);
        final f = ((local - 0.55) / 0.45).clamp(0.0, 1.0);
        angle = math.pi * (1 - Curves.easeInOut.transform(f));
        if (c.special && local >= 1) {
          final hold = (_pt - _starts[i] - _durs[i]) / 0.5;
          if (hold < 1) scale = 1 + 0.1 * math.sin(hold.clamp(0.0, 1.0) * math.pi);
        }
      case _Phase.done:
        break;
      case _Phase.collect:
        final k = Curves.easeInCubic.transform(((_pt - i * 0.05) / (_collectDur - 0.12)).clamp(0.0, 1.0));
        pos = Offset.lerp(slot, Offset(_size.width / 2, 24), k)!;
        scale = 1 - 0.65 * k;
        opacity = 1 - k;
      case _Phase.drop:
      case _Phase.idle:
      case _Phase.shake:
      case _Phase.burst:
        return const SizedBox.shrink();
    }
    final front = _CardFace(card: c, size: cs);
    final back = _CardBack(look: _look, size: cs);
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0015)
      ..rotateY(angle);
    return Positioned(
      left: pos.dx - cs.width / 2,
      top: pos.dy - cs.height / 2,
      width: cs.width,
      height: cs.height,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(
              scale: scale,
              child: Transform(
                alignment: Alignment.center,
                transform: m,
                child: angle <= math.pi / 2 ? front : Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: back),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _bezier(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return a * (u * u) + b * (2 * u * t) + c * (t * t);
  }

  Widget _header() {
    final prompt = switch (_phase) {
      _Phase.drop || _Phase.idle || _Phase.shake => _look.taps == 1
          ? 'Tap the chest to open it'
          : (_taps == 0 ? 'Tap the chest three times to open it' : 'Again! ${_look.taps - _taps} more'),
      _Phase.done || _Phase.collect => 'Your rewards',
      _ => '',
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_look.label, textAlign: TextAlign.center, style: EvochiText.section.copyWith(color: Colors.white, fontSize: 22)),
      const SizedBox(height: 4),
      AnimatedOpacity(
        opacity: prompt.isEmpty ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: Text(prompt.isEmpty ? ' ' : prompt, textAlign: TextAlign.center, style: EvochiText.caption.copyWith(color: const Color(0xCCFFFFFF))),
      ),
    ]);
  }

  Widget _footer() {
    if (_phase == _Phase.done || (_phase == _Phase.collect && !_reduced)) {
      return Center(
        child: SizedBox(
          width: 220,
          child: EvochiButton(label: 'Collect', onPressed: _collect, expand: true),
        ),
      );
    }
    if (_phase == _Phase.burst || _phase == _Phase.reveal) {
      return Center(
        child: TextButton(
          onPressed: _skip,
          child: Text('Skip', style: EvochiText.button.copyWith(color: const Color(0xCCFFFFFF), fontSize: 15)),
        ),
      );
    }
    return const SizedBox(height: 48);
  }
}

// ------------------------------------------------------------------ card faces
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.size});
  final _Card card;
  final Size size;
  @override
  Widget build(BuildContext context) {
    final col = card.color;
    final icon = size.width * 0.5;
    final Widget img = switch (card.kind) {
      'coins' => _iconImg('coin', icon),
      'glimmer' => _iconImg('glimmer', icon, fallback: 'gem'),
      _ => _itemImg(card.itemId ?? '', icon),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      decoration: BoxDecoration(
        color: EvochiColor.canvas,
        borderRadius: BorderRadius.circular(EvochiSpace.rM),
        border: Border.all(color: col, width: 3),
        boxShadow: [
          card.special
              ? BoxShadow(color: _a(col, 0.75), blurRadius: 18, spreadRadius: 1)
              : const BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        Expanded(child: Center(child: img)),
        const SizedBox(height: 2),
        Text(card.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: EvochiText.cardTitle.copyWith(fontSize: card.kind == 'item' ? 12.5 : 15, height: 1.1)),
        Text(card.sub, maxLines: 1, textAlign: TextAlign.center, style: EvochiText.tiny.copyWith(color: Color.lerp(col, EvochiColor.ink, 0.35))),
      ]),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.look, required this.size});
  final _TierLook look;
  final Size size;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(EvochiSpace.rM),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [look.glow, look.deep]),
          border: Border.all(color: const Color(0xD9FFFFFF), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Center(child: Opacity(opacity: 0.85, child: _iconImg('star', size.width * 0.42))),
      );
}

// ------------------------------------------------------------------ painters
class _BackPainter extends CustomPainter {
  _BackPainter({required this.center, required this.chestSize, required this.color, required this.glow, required this.rays, required this.rot});
  final Offset center;
  final double chestSize, glow, rays, rot;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rays > 0) {
      final r = chestSize * 1.7;
      const n = 14;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a0 = rot + i * 2 * math.pi / n;
        final a1 = a0 + 2 * math.pi / n * 0.42;
        path
          ..moveTo(center.dx, center.dy)
          ..lineTo(center.dx + math.cos(a0) * r, center.dy + math.sin(a0) * r)
          ..lineTo(center.dx + math.cos(a1) * r, center.dy + math.sin(a1) * r)
          ..close();
      }
      canvas.drawPath(path, Paint()..shader = ui.Gradient.radial(center, r, [_a(color, rays * 0.7), _a(color, 0)]));
    }
    if (glow > 0) {
      final r = chestSize * 0.9;
      canvas.drawCircle(center, r, Paint()..shader = ui.Gradient.radial(center, r, [_a(color, glow * 0.8), _a(color, 0)]));
    }
  }

  @override
  bool shouldRepaint(covariant _BackPainter old) =>
      old.center != center || old.chestSize != chestSize || old.glow != glow || old.rays != rays || old.rot != rot || old.color != color;
}

class _FxPainter extends CustomPainter {
  _FxPainter(List<_Particle> parts) : parts = List.of(parts);
  final List<_Particle> parts;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in parts) {
      final life = (p.age / p.life).clamp(0.0, 1.0);
      final fade = 1 - life;
      switch (p.kind) {
        case 0:
          paint.color = _a(p.color, fade * 0.55);
          canvas.drawCircle(Offset(p.x, p.y), p.size * (1 + life * 1.6), paint);
        case 1:
          paint.color = _a(p.color, fade);
          canvas.drawCircle(Offset(p.x, p.y), p.size * (0.5 + 0.5 * fade), paint);
        default:
          paint.color = _a(p.color, fade);
          canvas.drawPath(_star(Offset(p.x, p.y), p.size * (0.6 + 0.4 * math.sin(life * math.pi))), paint);
      }
    }
  }

  Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final rr = i.isEven ? r : r * 0.32;
      final x = c.dx + math.cos(a) * rr, y = c.dy + math.sin(a) * rr;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) => true;
}
