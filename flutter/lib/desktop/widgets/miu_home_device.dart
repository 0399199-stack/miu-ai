import 'package:flutter/material.dart';

import 'miu_glass.dart';

class MiuHomeDevice extends StatelessWidget {
  const MiuHomeDevice({
    Key? key,
    required this.name,
    required this.id,
    required this.details,
    required this.onConnect,
    required this.onView,
    required this.onRename,
    required this.menu,
    this.compact = false,
  }) : super(key: key);

  final String name;
  final String id;
  final String details;
  final VoidCallback onConnect;
  final VoidCallback onView;
  final VoidCallback onRename;
  final Widget menu;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFFA9BFD9) : const Color(0xFF6882A6);
    final title = Row(children: [
      Flexible(
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 4),
      IconButton(
        tooltip: '设置备注',
        onPressed: onRename,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.edit_outlined, size: 15, color: muted),
      ),
    ]);
    final metadata = Text(
      details.isEmpty ? 'ID $id' : 'ID $id · $details',
      style: TextStyle(fontSize: 12, color: muted),
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
    Widget controls() => Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2678FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('连接'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    dark ? const Color(0xFFCCE1FF) : const Color(0xFF234D87),
                backgroundColor:
                    const Color(0xFF8CBFFF).withOpacity(dark ? 0.09 : 0.08),
                minimumSize: const Size(0, 40),
                side:
                    BorderSide(color: const Color(0xFF9BC5FF).withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('仅观看'),
            ),
          ),
        ]);

    return MiuHoverSurface(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: compact
          ? Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF3886FF).withOpacity(0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.desktop_windows_rounded,
                    color: Color(0xFF3583EE), size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, metadata],
              )),
              const SizedBox(width: 16),
              SizedBox(width: 180, child: controls()),
              const SizedBox(width: 6),
              menu,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF72B1FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('最近连接',
                      style: TextStyle(fontSize: 11, color: muted)),
                ),
                const Spacer(),
                menu,
              ]),
              const SizedBox(height: 8),
              Container(
                height: 106,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xFF243D61), Color(0xFF172A44)]
                        : const [
                            Color(0xFFE7F2FF),
                            Color(0xFFCFE4FF),
                            Color(0xFFF2F8FF)
                          ],
                  ),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  Positioned(
                    right: -25,
                    top: -75,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 26),
                      ),
                    ),
                  ),
                  Icon(Icons.desktop_windows_rounded,
                      size: 62,
                      color: dark
                          ? const Color(0xFF8FC0FF)
                          : const Color(0xFF5D9EEE)),
                  Positioned(
                    bottom: 12,
                    right: 14,
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 19, color: Colors.white.withOpacity(0.85)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              title,
              metadata,
              const SizedBox(height: 14),
              controls(),
            ]),
    );
  }
}
