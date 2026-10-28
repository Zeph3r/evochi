// Renders the Wilds/mine entrance sheet (wilds/descent_sheet.dart) to PNGs for a look: the Wilds with F4
// reached, and the mine before its shaft (the deep way locked). 412 x 892 dp at 2x.
//
//   flutter test tool/shorts/descent_snap_test.dart      -> logs/descent_wilds.png, logs/descent_mine.png

import 'dart:io';
import 'dart:ui' as ui;

import 'package:evochi/app/theme.dart';
import 'package:evochi/controllers/game_controller.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/services/asset_manifest.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/data/local/local_store.dart';
import 'package:evochi/data/repositories/game_repository.dart';
import 'package:evochi/features/wilds/descent_sheet.dart';
import 'package:evochi/game/wilds/wilds.dart' as w;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'shorts.dart' show mochi;

const _dpr = 2.0;
const _size = Size(412, 892);

class _NoSave extends GameRepository {
  _NoSave() : super(local: MemoryStore());
  @override
  void save(GameState state) {}
}

void main() {
  setUpAll(() async {
    ensureTimeZones();
    for (final (family, files) in const [
      ('Nunito', ['assets/fonts/Nunito-Bold.ttf', 'assets/fonts/Nunito-ExtraBold.ttf', 'assets/fonts/Nunito-Black.ttf']),
      ('Lato', ['assets/fonts/Lato-Regular.ttf', 'assets/fonts/Lato-Bold.ttf', 'assets/fonts/Lato-Black.ttf']),
    ]) {
      final l = FontLoader(family);
      for (final f in files) {
        l.addFont(rootBundle.load(f));
      }
      await l.load();
    }
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await AssetManifest.load();
  });

  for (final mine in [false, true]) {
    testWidgets('snap the ${mine ? 'mine' : 'Wilds'} entrance', (tester) async {
      tester.view.physicalSize = Size(_size.width * _dpr, _size.height * _dpr);
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      final st = mochi('amber');
      if (!mine) {
        for (var f = 2; f <= 4; f++) {
          st.flags[w.reachFlag(f)] = true;
        }
      }
      final controller = GameController(repo: _NoSave())
        ..state = st
        ..ready = true;
      final shot = GlobalKey();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: evochiTheme(),
          builder: (context, child) => RepaintBoundary(key: shot, child: child),
          home: Builder(builder: (context) => Scaffold(
                backgroundColor: const Color(0xFF86B566),
                body: Center(child: ElevatedButton(onPressed: () => showDescentSheet(context, mine: mine), child: const Text('in'))),
              )),
        ),
      ));
      await tester.tap(find.text('in'));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final ro = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: _dpr);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        return bd!.buffer.asUint8List();
      });
      await tester.runAsync(() async => File('logs/descent_${mine ? 'mine' : 'wilds'}.png').writeAsBytesSync(png!));
    });
  }
}
