import 'dart:ui';

import 'package:flutter/material.dart';

class MiuBackdrop extends StatelessWidget {
  const MiuBackdrop({Key? key, required this.child}) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF111A2D), Color(0xFF1C2035), Color(0xFF182F3B)]
              : const [Color(0xFFF8FAFF), Color(0xFFEFF3FC), Color(0xFFF5F0FA)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -110,
            child: IgnorePointer(
              child: Container(
                width: 520,
                height: 520,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: dark
                      ? [const Color(0xFF5976D9).withOpacity(0.18), Colors.transparent]
                      : [const Color(0xFFA8C8FF).withOpacity(0.65), Colors.transparent]),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -230,
            left: -100,
            child: IgnorePointer(
              child: Container(
                width: 560,
                height: 560,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: dark
                      ? [const Color(0xFF886EC9).withOpacity(0.13), Colors.transparent]
                      : [const Color(0xFFD8C9FF).withOpacity(0.5), Colors.transparent]),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class MiuGlass extends StatelessWidget {
  const MiuGlass({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
  }) : super(key: key);

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.22 : 0.10),
            blurRadius: 36,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.06)]
                    : [Colors.white.withOpacity(0.78), Colors.white.withOpacity(0.48)],
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withOpacity(dark ? 0.20 : 0.86),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
    final animate = !MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0.0 : 1.0, end: 1.0),
      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
      curve: Curves.easeOutCubic,
      child: glass,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - progress)),
          child: child,
        ),
      ),
    );
  }
}
