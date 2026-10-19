// Static character sprite cut from the atlases (evolution strip, swatches, EvoDex, memorial).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/services/asset_manifest.dart';

class PetSprite extends StatefulWidget {
  const PetSprite({
    super.key,
    required this.stage,
    required this.palette,
    this.expr = 'default',
    this.view,
    this.overlays = const [],
    this.height = 80,
    this.silhouette = false,
    this.semanticLabel,
  });
  final int stage;
  final String palette;
  final String expr;
  final String? view; // front | left | back | right | top (turnaround)
  final List<String> overlays;
  final double height;
  final bool silhouette;
  final String? semanticLabel;

  @override
  State<PetSprite> createState() => _PetSpriteState();
}

class _PetSpriteState extends State<PetSprite> {
  ui.Image? _img;
  ui.Image? _ov;
  Rect? _src;
  int _req = 0; // only the latest load lands

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PetSprite old) {
    super.didUpdateWidget(old);
    // (the overlays and the size decide which sheet it draws from: a preview turning a piece on or off)
    if (old.stage != widget.stage ||
        old.palette != widget.palette ||
        old.expr != widget.expr ||
        old.view != widget.view ||
        old.overlays.join('+') != widget.overlays.join('+') ||
        (old.height <= 150) != (widget.height <= 150)) {
      _load();
    }
  }

  Future<void> _load() async {
    final req = ++_req;
    final m = AssetManifest.instance!;
    final e = m.char(widget.stage);
    String file;
    Rect src;
    final thumb = (widget.view == null && widget.overlays.isEmpty && widget.height <= 150) ? m.thumbRect(widget.stage, widget.palette, widget.expr) : null;
    if (thumb != null) {
      file = m.thumbsFile;
      src = thumb;
    } else if (widget.view != null) {
      file = artBase + e.turnFile(widget.palette);
      src = e.turnRect(widget.palette, widget.view!);
    } else {
      file = artBase + e.atlasFile(widget.palette);
      src = e.frame(widget.palette, widget.expr);
    }
    final img = await AtlasCache.load(file);
    ui.Image? ov;
    if (widget.overlays.isNotEmpty && widget.view == null) ov = await AtlasCache.load(artBase + e.overlaysFile);
    if (!mounted || req != _req) return;
    setState(() {
      _img = img;
      _ov = ov;
      _src = src;
    });
  }

  @override
  Widget build(BuildContext context) {
    final src = _src;
    final aspect = src == null ? 1.0 : src.width / src.height;
    return Semantics(
      label: widget.semanticLabel,
      image: widget.semanticLabel != null,
      child: SizedBox(
        height: widget.height,
        width: widget.height * aspect,
        child: _img == null
            ? const SizedBox.shrink()
            : CustomPaint(
                painter: _SpritePainter(
                  _img!,
                  src!,
                  _ov,
                  widget.view == null ? [for (final o in widget.overlays) AssetManifest.instance!.char(widget.stage).overlay(o)].whereType<Rect>().toList() : const [],
                  widget.silhouette,
                ),
              ),
      ),
    );
  }
}

/// Your Evochi as the encounter sees it (from behind): the untrimmed battle frame for an expression
/// with the equipped wearables drawn over it at the same frame size, so it can be placed by its
/// anchors. [width] is the frame's width on screen (the height follows the frame's aspect). The last
/// frame stays up while the next one loads, so expression changes never flash.
class BattleSprite extends StatefulWidget {
  const BattleSprite({super.key, required this.stage, required this.palette, this.expr = 'default', this.overlays = const [], required this.width});
  final int stage;
  final String palette;
  final String expr;
  final List<String> overlays;
  final double width;

  @override
  State<BattleSprite> createState() => _BattleSpriteState();
}

class _BattleSpriteState extends State<BattleSprite> {
  ui.Image? _img;
  ui.Image? _ov;
  Rect? _src;
  List<Rect> _ovRects = const [];
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BattleSprite old) {
    super.didUpdateWidget(old);
    if (old.stage != widget.stage || old.palette != widget.palette || old.expr != widget.expr || old.overlays.join('+') != widget.overlays.join('+')) _load();
  }

  Future<void> _load() async {
    final e = AssetManifest.instance!.char(widget.stage).battle;
    if (e == null) return;
    final req = ++_req;
    final src = e.frame(widget.palette, widget.expr);
    final img = await AtlasCache.load(e.atlasFile(widget.palette));
    ui.Image? ov;
    final rects = <Rect>[];
    if (widget.overlays.isNotEmpty) {
      for (final o in widget.overlays) {
        final r = e.overlay(o);
        if (r != null) rects.add(r);
      }
      if (rects.isNotEmpty) ov = await AtlasCache.load(e.overlaysFile);
    }
    if (!mounted || req != _req) return;
    setState(() {
      _img = img;
      _ov = ov;
      _src = src;
      _ovRects = rects;
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = AssetManifest.instance!.char(widget.stage).battle;
    final aspect = e == null ? 1.0 : e.w / e.h;
    return SizedBox(
      width: widget.width,
      height: widget.width / aspect,
      child: _img == null || _src == null ? const SizedBox.shrink() : CustomPaint(painter: _SpritePainter(_img!, _src!, _ov, _ovRects, false)),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.img, this.src, this.ov, this.ovRects, this.silhouette);
  final ui.Image img;
  final Rect src;
  final ui.Image? ov;
  final List<Rect> ovRects;
  final bool silhouette;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final p = Paint()..filterQuality = FilterQuality.medium;
    if (silhouette) p.colorFilter = const ColorFilter.mode(Color(0x55000000), BlendMode.srcIn);
    canvas.drawImageRect(img, src, dst, p);
    if (ov != null) {
      // overlay rects share the hero frame size, so they map onto the same destination
      for (final r in ovRects) {
        canvas.drawImageRect(ov!, r, dst, p);
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.img != img || old.src != src || old.ov != ov || old.silhouette != silhouette || old.ovRects.length != ovRects.length || !_sameRects(old.ovRects, ovRects);

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
