import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum TriageOutcome { safe, attention, emergency }

class TriageResultCard extends StatelessWidget {
  final TriageOutcome outcome;
  final String reason;
  final String nextStep;

  const TriageResultCard({
    super.key,
    required this.outcome,
    required this.reason,
    required this.nextStep,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _config(outcome);

    // Entrance animation — card eases up + fades in on first render.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 16),
          child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
        ),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cfg.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cfg.color.withValues(alpha: 0.35), width: 2),
          boxShadow: [
            BoxShadow(
              color: cfg.color.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Band banner ──────────────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Stack(
                children: [
                  // Safe-band celebration burst — concentric rings rippling
                  if (outcome == TriageOutcome.safe)
                    const Positioned.fill(child: _CelebrationBurst()),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                    decoration: BoxDecoration(color: cfg.color),
                    child: Row(
                      children: [
                        if (outcome == TriageOutcome.emergency)
                          const _PulseDot(color: Colors.white)
                        else if (outcome == TriageOutcome.safe)
                          const _BouncyCheck()
                        else
                          Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cfg.bandLabel,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cfg.subtitle,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Referral level chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            cfg.referralLevel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BodyRow(
                    icon: Icons.info_outline_rounded,
                    label: 'কারণ',
                    value: reason,
                    color: cfg.color,
                  ),
                  const SizedBox(height: 16),
                  Divider(color: cfg.color.withValues(alpha: 0.15), height: 1),
                  const SizedBox(height: 16),
                  _BodyRow(
                    icon: Icons.arrow_forward_ios_rounded,
                    label: 'পরবর্তী পদক্ষেপ',
                    value: nextStep,
                    color: cfg.color,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static _BandConfig _config(TriageOutcome outcome) => switch (outcome) {
        TriageOutcome.safe => _BandConfig(
            color: AppColors.safeGreen,
            bg: const Color(0xFFECFDF5),
            bandLabel: '🟢 সবুজ — নিরাপদ',
            subtitle: 'কোনো বিপদচিহ্ন নেই',
            referralLevel: 'বাড়িতে যত্ন',
          ),
        TriageOutcome.attention => _BandConfig(
            color: const Color(0xFFD97706),
            bg: const Color(0xFFFFFBEB),
            bandLabel: '🟡 হলুদ — মনোযোগ দরকার',
            subtitle: 'মাঝারি ঝুঁকি — PHC-তে যান',
            referralLevel: '২৪ ঘণ্টার মধ্যে PHC',
          ),
        TriageOutcome.emergency => _BandConfig(
            color: AppColors.emergencyRed,
            bg: const Color(0xFFFFEBEB),
            bandLabel: '🔴 লাল — জরুরি অবস্থা',
            subtitle: 'এখনই রেফার করুন',
            referralLevel: 'FRU / SNCU / DH',
          ),
      };
}

class _BandConfig {
  final Color color;
  final Color bg;
  final String bandLabel;
  final String subtitle;
  final String referralLevel;
  const _BandConfig({
    required this.color,
    required this.bg,
    required this.bandLabel,
    required this.subtitle,
    required this.referralLevel,
  });
}

class _BodyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BodyRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.onBackground,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Animated pulse dot for RED band ──────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.8, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.6),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bouncy checkmark for SAFE band ───────────────────────────────────────────
// One-shot scale-in + tiny spring overshoot — celebratory but not distracting.
class _BouncyCheck extends StatefulWidget {
  const _BouncyCheck();

  @override
  State<_BouncyCheck> createState() => _BouncyCheckState();
}

class _BouncyCheckState extends State<_BouncyCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, size: 16, color: AppColors.safeGreen),
      ),
    );
  }
}

// ── Celebration burst — concentric rings rippling outward, behind GREEN banner.
// Drawn as a soft animated overlay; never covers text (uses alpha < 0.35).
class _CelebrationBurst extends StatefulWidget {
  const _CelebrationBurst();

  @override
  State<_CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<_CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _BurstPainter(progress: _ctrl.value),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress; // 0..1
  _BurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width * 0.18, size.height / 2);
    final maxR = math.max(size.width, size.height) * 0.9;

    // 3 staggered rings — each starts at a different phase.
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final r = phase * maxR;
      final alpha = (1 - phase) * 0.28;
      if (alpha <= 0.01) continue;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(centre, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.progress != progress;
}
