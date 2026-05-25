import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../app/routes.dart';
import '../../../../shared/widgets/voice_orb.dart';
import '../../../../features/auth/controller/auth_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(
      const Duration(milliseconds: 2400),
      () {
        final auth = Get.find<AuthController>();
        final hasSession = auth.restoreSession();
        if (hasSession) {
          if (auth.user.value?.isAdmin == true) {
            Get.offAllNamed(AppRoutes.adminDashboard);
          } else {
            Get.offAllNamed(AppRoutes.home);
          }
        } else {
          Get.offNamed(AppRoutes.language);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.splash),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Orb — scales + fades in immediately
                _Reveal(
                  delay: const Duration(milliseconds: 0),
                  child: const VoiceOrb(size: 160),
                ),
                const SizedBox(height: 40),

                // Title — slides up after orb settles
                _Reveal(
                  delay: const Duration(milliseconds: 350),
                  child: Text(
                    'ASHA Mitra',
                    style: AppTextStyles.display.copyWith(
                      fontSize: 38,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle — lags title slightly
                _Reveal(
                  delay: const Duration(milliseconds: 600),
                  child: Text(
                    'Voice AI for Safer Care',
                    style: AppTextStyles.bodyLg.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                const Spacer(),

                // Tagline — appears last
                _Reveal(
                  delay: const Duration(milliseconds: 1000),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      'Powered by AI · Works Offline · Bangla First',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Internal helper — fades + slides its child in after `delay` ms.
class _Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _Reveal({required this.child, required this.delay});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.15),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
