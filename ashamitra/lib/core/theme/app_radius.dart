import 'package:flutter/widgets.dart';

/// Corner radius tokens. Use these instead of magic numbers like `14`, `18`.
class AppRadius {
  AppRadius._();

  static const double sm   = 8;   // chips, small badges
  static const double md   = 12;  // inputs, small cards
  static const double lg   = 16;  // standard cards
  static const double xl   = 20;  // hero cards, sheets
  static const double xxl  = 28;  // modal sheets, large containers
  static const double pill = 999; // pill-shaped buttons/chips

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static BorderRadius get smR  => all(sm);
  static BorderRadius get mdR  => all(md);
  static BorderRadius get lgR  => all(lg);
  static BorderRadius get xlR  => all(xl);
  static BorderRadius get xxlR => all(xxl);
  static BorderRadius get pillR => all(pill);
}
