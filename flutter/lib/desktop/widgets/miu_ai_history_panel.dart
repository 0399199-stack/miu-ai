import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';

OverlayEntry showMiuAiHistoryPanel(
    BuildContext context, FFI ffi, VoidCallback onClose) {
  final entry = OverlayEntry(
    builder: (_) => LayoutBuilder(
      builder: (_, constraints) => _MiuAiHistoryPanel(
        chatModel: ffi.chatModel,
        viewportSize: constraints.biggest,
        onClose: onClose,
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}

class _MiuAiHistoryPanel extends StatefulWidget {
  const _MiuAiHistoryPanel({
    required this.chatModel,
    required this.viewportSize,
    required this.onClose,
  });

  final ChatModel chatModel;
  final Size viewportSize;
  final VoidCallback onClose;

  @override
  State<_MiuAiHistoryPanel> createState() => _MiuAiHistoryPanelState();
}

class _MiuAiHistoryPanelState extends State<_MiuAiHistoryPanel> {
  Offset? _position;
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await widget.chatModel.refreshMiuAiHistory();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(420.0, widget.viewportSize.width - 20);
    final height = math.min(560.0, widget.viewportSize.height - 20);
    final initial = Offset(math.max(10, widget.viewportSize.width - width - 22), 62);
    final position = _position ?? initial;
    return Stack(children: [
      Positioned(
        left: position.dx.clamp(10, math.max(10, widget.viewportSize.width - width - 10)),
        top: position.dy.clamp(10, math.max(10, widget.viewportSize.height - height - 10)),
        width: width,
        height: height,
        child: Material(
          color: const Color(0xFFF8FAFF).withOpacity(0.96),
          elevation: 16,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Column(children: [
              GestureDetector(
                onPanUpdate: (details) => setState(() {
                  _position = Offset(
                    (position.dx + details.delta.dx).clamp(
                        10, math.max(10, widget.viewportSize.width - width - 10)),
                    (position.dy + details.delta.dy).clamp(
                        10, math.max(10, widget.viewportSize.height - height - 10)),
                  );
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome_rounded, color: Color(0xFF617BE9)),
                    const SizedBox(width: 9),
                    const Expanded(child: Text('B 与 Miu AI',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                    IconButton(
                      tooltip: '同步最近记录',
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: AnimatedBuilder(
                animation: widget.chatModel,
                builder: (context, _) {
                  final history = widget.chatModel.miuAiHistory;
                  if (history.isEmpty) {
                    return const Center(child: Text('B 机暂无 Miu AI 聊天记录'));
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      return Align(
                        alignment: item.fromUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: width - 72),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 9),
                          decoration: BoxDecoration(
                            color: item.fromUser
                                ? const Color(0xFF617BE9)
                                : Colors.white.withOpacity(0.86),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: SelectableText(item.text,
                            style: TextStyle(color: item.fromUser
                                ? Colors.white : const Color(0xFF263252))),
                        ),
                      );
                    },
                  );
                },
              )),
            ]),
          ),
        ),
      ),
    ]);
  }
}
