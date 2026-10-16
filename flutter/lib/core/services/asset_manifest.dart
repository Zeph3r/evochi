// Art manifest produced by tools/art/build_web_assets.py: atlas rects, anchors, scene metadata.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const artBase = 'assets/art/';
const audioBase = 'assets/audio/';

class CharEntry {
  CharEntry(this.j);
  final Map<String, dynamic> j;
  double get scale => (j['scale'] as num).toDouble();
  double get w => (j['w'] as num).toDouble();
  double get h => (j['h'] as num).toDouble();
  List<String> get expressions => (j['expressions'] as List).cast<String>();
  Offset anchor(String name) {
    final a = (j['anchors'] as Map)[name] as List;
    return Offset((a[0] as num).toDouble(), (a[1] as num).toDouble());
  }

  String atlasFile(String palette) => (j['atlas'] as Map)[palette]['file'] as String;
  Rect frame(String palette, String expr) {
    var i = expressions.indexOf(expr);
    if (i < 0) i = 0;
    final r = ((j['atlas'] as Map)[palette]['rects'] as List)[i] as List;
    return _rect(r);
  }

  String get overlaysFile => (j['overlays'] as Map)['file'] as String;
  Rect? overlay(String itemId) {
    final r = ((j['overlays'] as Map)['rects'] as Map)[itemId];
    return r == null ? null : _rect(r as List);
  }

  String turnFile(String palette) => (j['turn'] as Map)[palette]['file'] as String;
  Rect turnRect(String palette, String view) => _rect(((j['turn'] as Map)[palette]['rects'] as Map)[view] as List);
}

Rect _rect(List r) => Rect.fromLTWH((r[0] as num).toDouble(), (r[1] as num).toDouble(), (r[2] as num).toDouble(), (r[3] as num).toDouble());

class HabitatEntry {
  HabitatEntry(this.j);
  final Map<String, dynamic> j;
  double get w => (j['w'] as num).toDouble();
  double get h => (j['h'] as num).toDouble();
  List<String> get layerNames => (j['layers'] as Map).keys.cast<String>().toList();
  String? layer(String name) => (j['layers'] as Map)[name] as String?;
  Offset get pet => Offset(((j['pet'] as List)[0] as num).toDouble(), ((j['pet'] as List)[1] as num).toDouble());
  double get petPxPerUnit => (j['petPxPerUnit'] as num).toDouble();
  Map<String, dynamic> get decor => ((j['decor'] as Map?) ?? const {}).cast<String, dynamic>();
}

class AssetManifest {
  AssetManifest(this.j);
  final Map<String, dynamic> j;

  static AssetManifest? instance;

  static Future<AssetManifest> load() async {
    final text = await rootBundle.loadString('${artBase}manifest.json');
    instance = AssetManifest((jsonDecode(text) as Map).cast<String, dynamic>());
    return instance!;
  }

  CharEntry char(int stage) => CharEntry(((j['chars'] as Map)['s0$stage'] as Map).cast<String, dynamic>());
  HabitatEntry habitat(String name) => HabitatEntry(((j['habitats'] as Map)[name] as Map).cast<String, dynamic>());
  String thumb(String name) => artBase + ((j['habitats'] as Map)['thumbs'] as Map)[name];
  String icon(String k) => artBase + (j['icons'] as Map)[k];
  String item(String k) => artBase + (j['items'] as Map)[k];
  String title(String k) => artBase + ((j['titles'] as Map)[k] as Map)['file'];
  Size titleSize(String k) {
    final t = (j['titles'] as Map)[k] as Map;
    return Size((t['w'] as num).toDouble(), (t['h'] as num).toDouble());
  }

  String? audio(String k) {
    final a = (j['audio'] as Map)[k] as String?;
    return a == null ? null : audioBase + a;
  }

  Rect? thumbRect(int stage, String palette, String expr) {
    final r = ((j['thumbs'] as Map)['rects'] as Map)['$stage|$palette|$expr'];
    return r == null ? null : _rect(r as List);
  }

  String get thumbsFile => artBase + ((j['thumbs'] as Map)['file'] as String);

  VillageArt get village => VillageArt((j['village'] as Map).cast<String, dynamic>());
}

/// Village Tales art: villager sprites (5 expressions), the Square plate in three states with pin
/// anchors, the three interiors and the Waystone close-up.
class VillageArt {
  VillageArt(this.j);
  final Map<String, dynamic> j;

  Map<String, dynamic> _npc(String npcId) => ((j['npcs'] as Map)[npcId.replaceFirst('npc_', '')] as Map).cast<String, dynamic>();

  String npc(String npcId, [String expr = 'neutral']) {
    final e = _npc(npcId)['expr'] as Map;
    return artBase + ((e[expr] ?? e['neutral']) as String);
  }

  /// Where the feet touch the floor, as a fraction of the sprite (for the contact shadow).
  Offset npcGround(String npcId) {
    final n = _npc(npcId);
    final g = n['ground'] as List;
    return Offset((g[0] as num).toDouble() / (n['w'] as num).toDouble(), (g[1] as num).toDouble() / (n['h'] as num).toDouble());
  }

  Size npcSize(String npcId) {
    final n = _npc(npcId);
    return Size((n['w'] as num).toDouble(), (n['h'] as num).toDouble());
  }

  Map<String, dynamic> get _square => (j['square'] as Map).cast<String, dynamic>();
  Size get squareSize => Size((_square['w'] as num).toDouble(), (_square['h'] as num).toDouble());

  /// The Square in its current story state.
  String square({required bool lampLit, required bool restored}) =>
      artBase + (_square[restored ? 'waystone_restored' : (lampLit ? 'lamp_lit' : 'day_dim')] as String);

  Offset anchor(String id) {
    final a = (_square['anchors'] as Map)[id] as List;
    return Offset((a[0] as num).toDouble(), (a[1] as num).toDouble());
  }

  String place(String id) => artBase + ((j['places'] as Map)[id]['file'] as String);
  Size placeSize(String id) {
    final p = (j['places'] as Map)[id] as Map;
    return Size((p['w'] as num).toDouble(), (p['h'] as num).toDouble());
  }

  String waystone({required bool restored}) => artBase + ((j['waystone'] as Map)[restored ? 'restored' : 'dormant'] as String);
  Size get waystoneSize {
    final w = j['waystone'] as Map;
    return Size((w['w'] as num).toDouble(), (w['h'] as num).toDouble());
  }
}

/// Decoded ui.Image cache for atlases drawn by CustomPainters.
class AtlasCache {
  static final Map<String, ui.Image> _done = {};
  static final Map<String, Future<ui.Image>> _loading = {};

  static ui.Image? peek(String path) => _done[path];

  static Future<ui.Image> load(String path) {
    final d = _done[path];
    if (d != null) return Future.value(d);
    return _loading.putIfAbsent(path, () async {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _done[path] = frame.image;
      _loading.remove(path);
      return frame.image;
    });
  }
}
