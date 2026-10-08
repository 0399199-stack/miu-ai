import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Recent B-side pet conversation. This option contains chat text, never a key.
class MiuAiHistoryEntry {
  const MiuAiHistoryEntry(this.id, this.text, {required this.fromUser});

  final int id;
  final String text;
  final bool fromUser;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'fromUser': fromUser,
      };
}

class MiuAiHistoryStore {
  MiuAiHistoryStore._()
      : _read = (() => bind.mainGetLocalOption(key: _optionKey)),
        _write =
            ((value) => bind.mainSetLocalOption(key: _optionKey, value: value));

  MiuAiHistoryStore.forTesting({
    required String Function() read,
    required Future<void> Function(String) write,
  })  : _read = read,
        _write = write;

  static final instance = MiuAiHistoryStore._();
  static const _optionKey = 'miu-ai-history-v1';
  static const _maxEntries = 24;
  static const _maxTextLength = 4000;
  final String Function() _read;
  final Future<void> Function(String) _write;
  final List<MiuAiHistoryEntry> _entries = [];
  Future<void> _lastWrite = Future.value();
  bool _loaded = false;
  bool _saveWarningShown = false;

  List<MiuAiHistoryEntry> get recent {
    _ensureLoaded();
    return List.unmodifiable(_entries);
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = jsonDecode(_read());
      if (raw is! List) return;
      for (final value in raw) {
        if (value is! Map) continue;
        final id = value['id'];
        final text = value['text'];
        final fromUser = value['fromUser'];
        if (id is! int ||
            id < 1 ||
            text is! String ||
            text.isEmpty ||
            text.length > _maxTextLength ||
            fromUser is! bool ||
            _entries.any((entry) => entry.id == id)) continue;
        _entries.add(MiuAiHistoryEntry(id, text, fromUser: fromUser));
        if (_entries.length == _maxEntries) break;
      }
      _entries.sort((a, b) => b.id.compareTo(a.id));
    } catch (_) {
      // An absent or damaged local option starts an empty conversation.
    }
  }

  Future<void> add(String text, {required bool fromUser}) {
    _ensureLoaded();
    final content = text.trim();
    if (content.isEmpty) return Future.value();
    var end = content.length > _maxTextLength ? _maxTextLength : content.length;
    if (end < content.length &&
        content.codeUnitAt(end - 1) >= 0xD800 &&
        content.codeUnitAt(end - 1) <= 0xDBFF) end--;
    final id = DateTime.now().microsecondsSinceEpoch;
    _entries.insert(
        0,
        MiuAiHistoryEntry(
            _entries.isNotEmpty && id <= _entries.first.id
                ? _entries.first.id + 1
                : id,
            content.substring(0, end),
            fromUser: fromUser));
    if (_entries.length > _maxEntries) _entries.removeLast();
    final snapshot =
        jsonEncode(_entries.map((entry) => entry.toJson()).toList());
    _lastWrite = _lastWrite.then((_) => _write(snapshot)).catchError((_) {
      if (!_saveWarningShown) {
        _saveWarningShown = true;
        debugPrint('Miu AI: recent chat history could not be saved locally.');
      }
    });
    return _lastWrite;
  }

  /// Builds one bounded control reply. `before` is inclusive; `offset` resumes
  /// a long message without dropping its remainder on the next request.
  Map<String, dynamic> page({int? before, int offset = 0}) {
    _ensureLoaded();
    final remaining = _entries
        .where((entry) => before == null || entry.id <= before)
        .toList();
    if (remaining.isEmpty ||
        offset < 0 ||
        offset > remaining.first.text.length) {
      return {'entries': <Map<String, dynamic>>[], 'done': true};
    }
    final parts = <Map<String, dynamic>>[];
    for (final entry in remaining) {
      final start = parts.isEmpty ? offset : 0;
      var end = entry.text.length;
      Map<String, dynamic> part(int length) => {
            'id': entry.id,
            'fromUser': entry.fromUser,
            'text': entry.text.substring(start, length),
            'complete': length == entry.text.length,
          };
      bool fits(int length) =>
          utf8
              .encode(jsonEncode({
                'entries': [...parts, part(length)]
              }))
              .length <=
          2800;
      if (!fits(end)) {
        final boundaries = <int>[];
        var position = start;
        for (final rune in entry.text.substring(start).runes) {
          position += rune > 0xFFFF ? 2 : 1;
          boundaries.add(position);
        }
        if (boundaries.isEmpty) break;
        var low = 0;
        var high = boundaries.length - 1;
        while (low < high) {
          final mid = (low + high + 1) ~/ 2;
          if (fits(boundaries[mid])) {
            low = mid;
          } else {
            high = mid - 1;
          }
        }
        end = boundaries[low];
        if (!fits(end)) break;
      }
      if (end <= start) break;
      parts.add(part(end));
      if (end < entry.text.length) {
        return {
          'entries': parts,
          'done': false,
          'nextBefore': entry.id,
          'nextOffset': end,
        };
      }
    }
    if (parts.isEmpty) return {'entries': parts, 'done': true};
    final oldest = parts.last['id'] as int;
    final more = _entries.any((entry) => entry.id < oldest);
    return {
      'entries': parts,
      'done': !more,
      if (more) 'nextBefore': oldest - 1,
      if (more) 'nextOffset': 0,
    };
  }
}
