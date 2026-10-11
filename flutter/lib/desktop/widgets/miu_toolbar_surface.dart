import 'package:flutter/material.dart';

import 'miu_glass.dart';

const miuToolbarInk = Color(0xFF20355D);
const miuToolbarBlue = Color(0xFF317CFF);

class MiuToolbarMenuBar extends StatelessWidget {
  const MiuToolbarMenuBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MenuBar(
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      elevation: WidgetStatePropertyAll(0),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
      side: WidgetStatePropertyAll(BorderSide.none),
    ),
    children: [child],
  );
}

class MiuToolbarChip extends StatefulWidget {
  const MiuToolbarChip({super.key, required this.icon, this.label,
    this.onPressed, this.selected = false, this.danger = false,
    this.dropdown = false, this.status, this.badge = 0, this.tooltip});

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool selected, danger, dropdown;
  final Color? status;
  final int badge;
  final String? tooltip;

  @override
  State<MiuToolbarChip> createState() => _MiuToolbarChipState();
}

class _MiuToolbarChipState extends State<MiuToolbarChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = widget.danger ? Colors.white : widget.selected
        ? miuToolbarBlue : dark ? const Color(0xFFDEEAFF) : miuToolbarInk;
    final enabled = widget.onPressed != null;
    final background = widget.danger ? const Color(0xFFFF6073)
        : widget.selected || _hover ? miuToolbarBlue.withOpacity(dark ? .24 : .12)
        : Colors.white.withOpacity(dark ? .06 : .34);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Tooltip(
        message: widget.tooltip ?? widget.label ?? '',
        child: AnimatedScale(
          scale: _hover && enabled ? 1.025 : 1,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: miuToolbarBlue.withOpacity(.10)),
              boxShadow: _hover && enabled ? [BoxShadow(
                color: miuToolbarBlue.withOpacity(.10), blurRadius: 10,
                offset: const Offset(0, 3))] : null,
            ),
            child: TextButton(
              onHover: (value) => setState(() => _hover = value),
              onPressed: !enabled ? null : () {
                if (!widget.dropdown) {
                  Actions.maybeInvoke(context, const DismissIntent());
                }
                widget.onPressed!();
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(36, 38),
                padding: EdgeInsets.symmetric(horizontal: widget.label == null ? 9 : 12),
                foregroundColor: ink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Opacity(
                opacity: enabled ? 1 : .42,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.icon, size: 18, color: ink),
                  if (widget.label != null) ...[
                    const SizedBox(width: 6),
                    Text(widget.label!, style: TextStyle(color: ink, fontSize: 12,
                        fontWeight: FontWeight.w600)),
                  ],
                  if (widget.status != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.circle, size: 7, color: widget.status),
                  ],
                  if (widget.badge > 0) ...[
                    const SizedBox(width: 5),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFFF6073),
                        borderRadius: BorderRadius.circular(9)),
                      child: Text(widget.badge > 9 ? '9+' : '${widget.badge}',
                        style: const TextStyle(color: Colors.white, fontSize: 10))),
                  ],
                  if (widget.dropdown) ...[
                    const SizedBox(width: 3), Icon(Icons.expand_more_rounded, size: 15, color: ink),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MiuToolbarMenu extends StatefulWidget {
  const MiuToolbarMenu({super.key, required this.icon, required this.label,
    required this.builder, this.status, this.badge = 0, this.width = 340,
    this.onDismiss});

  final IconData icon;
  final String label;
  final Widget Function(BuildContext, VoidCallback) builder;
  final Color? status;
  final int badge;
  final double width;
  final VoidCallback? onDismiss;

  @override
  State<MiuToolbarMenu> createState() => _MiuToolbarMenuState();
}

class _MiuToolbarMenuState extends State<MiuToolbarMenu> {
  final _controller = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return MenuAnchor(
      controller: _controller,
      clipBehavior: Clip.none,
      consumeOutsideTap: true,
      onOpen: () => setState(() => _open = true),
      onClose: () {
        setState(() => _open = false);
        widget.onDismiss?.call();
      },
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        side: WidgetStatePropertyAll(BorderSide.none),
      ),
      alignmentOffset: const Offset(0, 8),
      builder: (context, controller, child) => MiuToolbarChip(
        icon: widget.icon, label: widget.label, selected: _open,
        status: widget.status, badge: widget.badge, dropdown: true,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SizedBox(
          width: widget.width.clamp(0, (size.width - 32).clamp(0, double.infinity)),
          child: MiuGlass(radius: 22, padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: (size.height - 130).clamp(120, 760)),
              child: SingleChildScrollView(
                primary: false,
                child: widget.builder(context, _controller.close),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MiuPanelHeading extends StatelessWidget {
  const MiuPanelHeading(this.title, {super.key, required this.onClose});
  final String title;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
    IconButton(tooltip: '关闭', onPressed: onClose,
      icon: const Icon(Icons.close_rounded, size: 19)),
  ]);
}

class MiuPanelAction extends StatelessWidget {
  const MiuPanelAction({super.key, required this.icon, required this.label, this.onPressed, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    leading: Icon(icon, size: 20, color: miuToolbarBlue),
    title: Text(label),
    trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 18),
    enabled: onPressed != null, onTap: onPressed,
  );
}
