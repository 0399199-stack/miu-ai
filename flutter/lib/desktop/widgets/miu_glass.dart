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
              : const [Color(0xFFF6FAFF), Color(0xFFE7F1FF), Color(0xFFF2F8FF)],
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
                      ? [const Color(0xFF5976D9).withOpacity(0.18), const Color(0x005976D9)]
                      : [const Color(0xFFA5D0FF).withOpacity(0.62), const Color(0x00A5D0FF)]),
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
                      ? [const Color(0xFF886EC9).withOpacity(0.13), const Color(0x00886EC9)]
                      : [const Color(0xFFB9DCFF).withOpacity(0.48), const Color(0x00B9DCFF)]),
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
            color: dark
                ? Colors.black.withOpacity(0.22)
                : const Color(0xFF497BB8).withOpacity(0.09),
            blurRadius: 28,
            offset: const Offset(0, 8),
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
                    : [Colors.white.withOpacity(0.86), Colors.white.withOpacity(0.58)],
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

class MiuHoverSurface extends StatefulWidget {
  const MiuHoverSurface({
    Key? key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
  }) : super(key: key);

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  @override
  State<MiuHoverSurface> createState() => _MiuHoverSurfaceState();
}

class _MiuHoverSurfaceState extends State<MiuHoverSurface> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = _hover || _focused;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, active && animate ? -2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3979D1).withOpacity(active ? 0.13 : 0.04),
              blurRadius: active ? 24 : 12,
              offset: Offset(0, active ? 8 : 3),
            ),
          ],
        ),
        child: Material(
          color: dark
              ? Color(active ? 0xFF263A54 : 0xFF202E43)
              : Colors.white.withOpacity(active ? 0.96 : 0.75),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.radius),
            side: BorderSide(
              color: active
                  ? const Color(0xFFAACDFF)
                  : Colors.white.withOpacity(dark ? 0.12 : 0.9),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _focused = value),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
