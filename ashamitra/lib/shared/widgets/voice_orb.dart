import 'dart:math';
import 'package:flutter/material.dart';

enum OrbState { idle, listening, processing }

class VoiceOrb extends StatefulWidget {
  final OrbState state;
  final double size;

  const VoiceOrb({super.key, this.state = OrbState.idle, this.size = 140});

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _rotateCtrl;
  late final AnimationController _glowCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    // Subtle breathing — 0.96 → 1.04 instead of 0.93 → 1.07 (less twitchy)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    _glowAnim = Tween<double>(begin: 0.20, end: 0.50).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Color get _orbColor => switch (widget.state) {
        OrbState.listening => const Color(0xFF22C55E),
        OrbState.processing => const Color(0xFF06B6D4),
        OrbState.idle => const Color(0xFF4F46E5),
      };

  IconData get _orbIcon => switch (widget.state) {
        OrbState.listening => Icons.graphic_eq,
        OrbState.processing => Icons.psychology_alt,
        OrbState.idle => Icons.mic,
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _rotateCtrl, _glowAnim]),
      builder: (_, __) {
        return SizedBox(
          width: s * 1.4,
          height: s * 1.4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring — soft halo that breathes
              Container(
                width: s * 1.3,
                height: s * 1.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _orbColor.withValues(alpha: _glowAnim.value),
                      blurRadius: 44,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
              // Pulsing outer ring
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: s * 1.15,
                  height: s * 1.15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _orbColor.withValues(alpha: 0.22),
                      width: 2,
                    ),
                  ),
                ),
              ),
              // Rotating sweep gradient ring
              Transform.rotate(
                angle: _rotateCtrl.value * 2 * pi,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        _orbColor.withValues(alpha: 0.0),
                        _orbColor.withValues(alpha: 0.45),
                        _orbColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Inner core orb — breathes in sync
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: s * 0.80,
                  height: s * 0.80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.95),
                        _orbColor.withValues(alpha: 0.75),
                        _orbColor,
                      ],
                      center: const Alignment(-0.3, -0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _orbColor.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  // Idle = show the AshaMitra brand mark so the worker
                  // sees the app's own symbol at rest. Listening /
                  // processing keep their dynamic state icons (waveform
                  // / thinking) since those communicate what's happening.
                  child: Center(
                    child: widget.state == OrbState.idle
                        ? ClipOval(
                            child: Padding(
                              padding: EdgeInsets.all(s * 0.08),
                              child: Image.asset(
                                'assets/images/ashalogo.png',
                                fit: BoxFit.contain,
                                color: Colors.white,
                                colorBlendMode: BlendMode.srcIn,
                              ),
                            ),
                          )
                        : Icon(_orbIcon, color: Colors.white, size: s * 0.30),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
