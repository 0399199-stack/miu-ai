import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class MiuDisplayPanel extends StatefulWidget {
  const MiuDisplayPanel({
    Key? key,
    required this.id,
    required this.ffi,
    required this.onClose,
    this.customScaleControls,
    this.monitors,
    this.sessionActions,
    this.onAdvanced,
  }) : super(key: key);

  final String id;
  final FFI ffi;
  final VoidCallback onClose;
  final Widget? customScaleControls;
  final Widget? monitors;
  final Widget? sessionActions;
  final VoidCallback? onAdvanced;

  @override
  State<MiuDisplayPanel> createState() => _MiuDisplayPanelState();
}

class _MiuDisplayPanelState extends State<MiuDisplayPanel> {
  Future<List<Object>>? _menus;
  String? _viewStyle;
  String? _quality;
  String? _codec;
  bool? _showQuality;
  bool _changingQuality = false;
  final Map<int, bool> _cursorValues = {};

  Future<List<Object>> _loadMenus() => Future.wait<Object>([
        toolbarViewStyle(context, widget.id, widget.ffi),
        toolbarImageQuality(context, widget.id, widget.ffi),
        toolbarCodec(context, widget.id, widget.ffi),
        if (widget.ffi.connType == ConnType.defaultConn)
          toolbarCursor(context, widget.id, widget.ffi)
        else
          Future.value(<TToggleMenu>[]),
      ]);

  Future<void> _toggleQualityMonitor(bool value) async {
    if (_changingQuality) return;
    setState(() => _changingQuality = true);
    const option = 'show-quality-monitor';
    try {
      final current = bind.sessionGetToggleOptionSync(
          sessionId: widget.ffi.sessionId, arg: option);
      if (current != value) {
        await bind.sessionToggleOption(
            sessionId: widget.ffi.sessionId, value: option);
      }
      widget.ffi.qualityMonitorModel
          .checkShowQualityMonitor(widget.ffi.sessionId);
      if (mounted) {
        setState(() => _showQuality = bind.sessionGetToggleOptionSync(
            sessionId: widget.ffi.sessionId, arg: option));
      }
    } finally {
      if (mounted) setState(() => _changingQuality = false);
    }
  }

  Widget _choices(
    String title,
    List<TRadioMenu<String>> options,
    String? selected,
    ValueChanged<String> onSelected, {
    Map<String, String> labels = const {},
    int columns = 3,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final value = selected ?? (options.isEmpty ? '' : options.first.groupValue);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 9),
      LayoutBuilder(builder: (context, constraints) {
        final count = options.length < columns ? options.length : columns;
        if (count == 0) return const SizedBox.shrink();
        final width = (constraints.maxWidth - 7 * (count - 1)) / count;
        return Wrap(spacing: 7, runSpacing: 7, children: [
          for (final option in options)
            SizedBox(
              width: width,
              child: Semantics(
                selected: option.value == value,
                child: OutlinedButton(
                  onPressed: option.onChanged == null
                      ? null
                      : () {
                          option.onChanged?.call(option.value);
                          onSelected(option.value);
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: option.value == value
                        ? (dark
                            ? const Color(0xFFBBD9FF)
                            : const Color(0xFF176BEA))
                        : (dark
                            ? const Color(0xFFBECEE4)
                            : const Color(0xFF405C83)),
                    backgroundColor: option.value == value
                        ? const Color(0xFF458DFF)
                            .withOpacity(dark ? 0.22 : 0.14)
                        : Colors.white.withOpacity(dark ? 0.04 : 0.35),
                    side: BorderSide(
                      color: option.value == value
                          ? const Color(0xFF72A9FF).withOpacity(0.6)
                          : const Color(0xFF9ABDE9).withOpacity(0.15),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: labels.containsKey(option.value)
                      ? Text(labels[option.value]!, textAlign: TextAlign.center)
                      : option.child,
                ),
              ),
            ),
        ]);
      }),
    ]);
  }

  Widget _toggle(Widget label, bool value, ValueChanged<bool>? onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(
              child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 13), child: label)),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: const Color(0xFF2678FF),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    _menus ??= _loadMenus();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.desktop_windows_outlined,
            size: 20, color: Color(0xFF377BE1)),
        const SizedBox(width: 9),
        const Expanded(
            child: Text('显示设置',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        IconButton(
          tooltip: translate('Close'),
          onPressed: widget.onClose,
          icon: const Icon(Icons.close_rounded, size: 20),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
        ),
      ]),
      const SizedBox(height: 16),
      FutureBuilder<List<Object>>(
        future: _menus,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(children: [
              const Text('暂时无法读取显示设置'),
              TextButton(
                  onPressed: () => setState(() => _menus = null),
                  child: const Text('重新读取')),
            ]);
          }
          if (!snapshot.hasData) {
            return const Padding(
                padding: EdgeInsets.all(24),
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final styles = snapshot.data![0] as List<TRadioMenu<String>>;
          final qualities = snapshot.data![1] as List<TRadioMenu<String>>;
          final codecs = snapshot.data![2] as List<TRadioMenu<String>>;
          final cursors = snapshot.data![3] as List<TToggleMenu>;
          final viewStyle =
              _viewStyle ?? (styles.isEmpty ? '' : styles.first.groupValue);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _choices('缩放', styles, _viewStyle,
                    (value) => setState(() => _viewStyle = value),
                    labels: const {
                      kRemoteViewStyleOriginal: '原始尺寸',
                      kRemoteViewStyleAdaptive: '适应窗口',
                      kRemoteViewStyleCustom: '自定义',
                    }),
                if (viewStyle == kRemoteViewStyleCustom &&
                    widget.customScaleControls != null) ...[
                  const SizedBox(height: 8),
                  widget.customScaleControls!,
                ],
                const SizedBox(height: 18),
                _choices('画质', qualities, _quality,
                    (value) => setState(() => _quality = value),
                    columns: 2,
                    labels: const {
                      kRemoteImageQualityBest: '高清',
                      kRemoteImageQualityBalanced: '平衡',
                      kRemoteImageQualityLow: '流畅',
                      kRemoteImageQualityCustom: '自定义画质',
                    }),
                if (codecs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _choices('编码', codecs, _codec,
                      (value) => setState(() => _codec = value)),
                ],
                const SizedBox(height: 14),
                Divider(color: const Color(0xFF86B3ED).withOpacity(0.18)),
                _toggle(
                    Text(translate('Show quality monitor')),
                    _showQuality ??
                        bind.sessionGetToggleOptionSync(
                            sessionId: widget.ffi.sessionId,
                            arg: 'show-quality-monitor'),
                    _changingQuality ? null : _toggleQualityMonitor),
                for (var i = 0; i < cursors.length; i++)
                  _toggle(
                      cursors[i].child,
                      _cursorValues[i] ?? cursors[i].value,
                      cursors[i].onChanged == null
                          ? null
                          : (value) {
                              cursors[i].onChanged?.call(value);
                              setState(() => _cursorValues[i] = value);
                            }),
                if (widget.monitors != null) ...[
                  const SizedBox(height: 12),
                  widget.monitors!,
                ],
                if (widget.sessionActions != null) ...[
                  const SizedBox(height: 12),
                  widget.sessionActions!,
                ],
                if (widget.onAdvanced != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: widget.onAdvanced,
                    child: const Row(children: [
                      Icon(Icons.tune_rounded, size: 17),
                      SizedBox(width: 8),
                      Expanded(child: Text('更多显示选项')),
                      Icon(Icons.chevron_right_rounded, size: 19),
                    ]),
                  ),
                ],
              ]);
        },
      ),
    ]);
  }
}
