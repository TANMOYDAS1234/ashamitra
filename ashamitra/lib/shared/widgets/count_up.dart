import 'package:flutter/material.dart';

/// Animates a number rolling up from 0 → [value] over [duration].
///
/// Use for any visible count on screen (report totals, stats, etc.). Looks
/// significantly more alive than slapping the final number on without
/// animation. Re-animates when [value] changes.
///
/// Drop-in replacement for a `Text('$count', ...)`.
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;
  final String prefix;
  final String suffix;
  final TextAlign? textAlign;

  const CountUp({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 750),
    this.curve = Curves.easeOutCubic,
    this.prefix = '',
    this.suffix = '',
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (_, v, __) => Text(
        '$prefix${v.round()}$suffix',
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}
