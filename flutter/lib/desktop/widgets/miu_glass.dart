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
      child: child,
    );
  }
}

class MiuGlass extends StatelessWidget {
  const MiuGlass({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  }) : super(key: key);

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.64),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withOpacity(dark ? 0.13 : 0.85),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(dark ? 0.12 : 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
