import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class CP {
  // --- Color palette ---
  static const Color bg = Color(0xFF06080F);
  static const Color surface = Color(0xFF0A1020);
  static const Color card = Color(0xFF0C1525);

  static const Color cyan = Color(0xFF00E5FF);
  static const Color magenta = Color(0xFFFF2D78);
  static const Color yellow = Color(0xFFFFD700);

  static const Color text = Color(0xFFD8EEFF);
  static const Color textDim = Color(0xFF5A8AA8);
  static const Color textMuted = Color(0xFF2A4A6A);

  // --- Decorations ---
  static BoxDecoration get cardDecor => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cyan.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: cyan.withValues(alpha: 0.07),
            blurRadius: 14,
          ),
        ],
      );

  static BoxDecoration cardDecorOf(Color c, {double glowAlpha = 0.12}) =>
      BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: glowAlpha), blurRadius: 12)],
      );

  static List<BoxShadow> glow(Color c, {double r = 12, double a = 0.5}) =>
      [BoxShadow(color: c.withValues(alpha: a), blurRadius: r)];

  // --- Typography ---
  static TextStyle orbitron({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      GoogleFonts.orbitron(fontSize: size, fontWeight: weight, color: color ?? text);

  static TextStyle mono({double size = 13, Color? color}) =>
      GoogleFonts.shareTechMono(fontSize: size, color: color ?? textDim);

  static TextStyle rajdhani({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      GoogleFonts.rajdhani(fontSize: size, fontWeight: weight, color: color ?? text);

  // --- Reusable widgets ---
  static Widget neonDivider({Color color = cyan, double opacity = 0.25}) =>
      Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ]),
        ),
      );

  static Widget sectionLabel(String label, {Color accent = cyan}) => Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: accent,
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.7), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: orbitron(size: 11, weight: FontWeight.w800, color: text),
          ),
        ],
      );

  // Neon-bordered chip
  static Widget chip(String label, {Color color = cyan}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: mono(size: 11, color: color),
        ),
      );
}
