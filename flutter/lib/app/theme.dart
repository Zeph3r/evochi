// Visual system tokens (style guide §04-06, Appendix A). One theme source for every screen.

import 'package:flutter/material.dart';

class EvochiColor {
  static const ink = Color(0xFF3B2923);
  static const textSecondary = Color(0xFF684C3C);
  static const textHelper = Color(0xFF8E7462);
  static const canvas = Color(0xFFFFF9F0);
  static const panel = Color(0xFFF8EBDD);
  static const panel2 = Color(0xFFEED9C2);
  static const shell = Color(0xFFFFF0DE);
  static const inset = Color(0xFFF4E2CD);
  static const border = Color(0xFFC9A78C);
  static const cardEdge = Color(0xFFE3CBB1);
  static const cardBevel = Color(0xFFD8BD9F);
  static const wood = Color(0xFF76513B);
  static const gold100 = Color(0xFFFFE5A2);
  static const gold300 = Color(0xFFF9CA70);
  static const primary = Color(0xFFF4B84E);
  static const primaryShadow = Color(0xFFC8832C);
  static const gold900 = Color(0xFF80531F);
  static const meadow100 = Color(0xFFE5F2CF);
  static const meadow300 = Color(0xFFB7D98B);
  static const steps = Color(0xFF82B75E);
  static const healthy = Color(0xFF477B3A);
  static const sky100 = Color(0xFFD6EDFB);
  static const sky400 = Color(0xFF84C4E8);
  static const water = Color(0xFF399CC7);
  static const cheek = Color(0xFFEC947C);
  static const dead = Color(0xFFD85F51);
  static const sick = Color(0xFFDB9942);
  static const violet = Color(0xFFAA8BCF);
  static const foot = Color(0xFF926244);
  static const claw = Color(0xFFFFF3E7);
  static const track = Color(0xFF5C4637);
  static const dim = Color(0xFF201B17);
  static const hudPill = Color(0xC7342620);
}

class EvochiSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s6 = 24.0, s8 = 32.0;
  static const rS = 8.0, rM = 12.0, rL = 20.0;
  static const minTarget = 44.0;
}

class EvochiText {
  static const game = 'Nunito';
  static const body = 'Lato';
  static const pageTitle = TextStyle(fontFamily: game, fontWeight: FontWeight.w900, fontSize: 24, height: 1.2, color: EvochiColor.ink);
  static const section = TextStyle(fontFamily: game, fontWeight: FontWeight.w800, fontSize: 18, height: 1.25, color: EvochiColor.ink);
  static const cardTitle = TextStyle(fontFamily: game, fontWeight: FontWeight.w800, fontSize: 16, height: 1.3, color: EvochiColor.ink);
  static const button = TextStyle(fontFamily: game, fontWeight: FontWeight.w900, fontSize: 17, color: EvochiColor.ink);
  static const bodyText = TextStyle(fontFamily: body, fontWeight: FontWeight.w400, fontSize: 14, height: 1.43, color: EvochiColor.ink);
  static const caption = TextStyle(fontFamily: body, fontWeight: FontWeight.w400, fontSize: 12, height: 1.33, color: EvochiColor.textHelper);
  static const tag = TextStyle(fontFamily: game, fontWeight: FontWeight.w800, fontSize: 13, color: EvochiColor.textSecondary);
  static const number = TextStyle(fontFamily: game, fontWeight: FontWeight.w900, fontSize: 20, color: EvochiColor.ink, fontFeatures: [FontFeature.tabularFigures()]);
}

ThemeData evochiTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: EvochiText.body,
    scaffoldBackgroundColor: EvochiColor.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: EvochiColor.primary,
      primary: EvochiColor.primary,
      onPrimary: EvochiColor.ink,
      surface: EvochiColor.canvas,
      onSurface: EvochiColor.ink,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: EvochiColor.ink, displayColor: EvochiColor.ink),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: EvochiColor.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
  );
}
