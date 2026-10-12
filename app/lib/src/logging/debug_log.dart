import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:simutil_core/simutil_core.dart';

/// Where a [DebugEntry] came from.
enum DebugSource { mcp, command, state }

/// One line of the debug panel.
final class DebugEntry {
  DebugEntry(this.source, this.text, {this.error = false})
    : time = DateTime.now();

  final DateTime time;
  final DebugSource source;
  final String text;
  final bool error;
}

/// A shell command that has not exited yet.
final class RunningCommand {
  RunningCommand(this.text) : started = DateTime.now();

  final String text;
  final DateTime started;
}

/// In-memory log behind the debug panel: MCP calls, shell commands and
/// cubit state changes, plus the commands running right now. Kept while
/// the panel is hidden, so opening it shows what just happened.
class DebugLog extends ChangeNotifier {
  /// Oldest entries are dropped past this.
  static const maxEntries = 500;

  final _entries = Queue<DebugEntry>();
  final _running = <int, RunningCommand>{};
  var _nextId = 0;
  bool _visible = false;

  /// Oldest first.
  Iterable<DebugEntry> get entries => _entries;

  /// Commands that have not exited, oldest first.
  Iterable<RunningCommand> get running => _running.values;

  /// Whether the debug panel is shown.
  bool get visible => _visible;

  void toggle() {
    _visible = !_visible;
    notifyListeners();
  }

  void add(DebugSource source, String text, {bool error = false}) {
    _entries.addLast(DebugEntry(source, text, error: error));
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Marks [text] running; pass the id to [endCommand].
  int startCommand(String text) {
    final id = _nextId++;
    _running[id] = RunningCommand(text);
    notifyListeners();
    return id;
  }

  /// Logs command [id] as finished with [outcome].
  void endCommand(int id, String outcome, {bool error = false}) {
    final command = _running.remove(id);
    if (command == null) return;
    final ms = DateTime.now().difference(command.started).inMilliseconds;
    add(
      DebugSource.command,
      '${command.text}  → $outcome (${ms}ms)',
      error: error,
    );
  }
}

/// [CommandExec] that reports every command to a [DebugLog].
class LoggingCommandExec implements CommandExec {
  LoggingCommandExec(this._inner, this._log);

  final CommandExec _inner;
  final DebugLog _log;

  @override
  Future<CommandResult> run(
    String command, {
    List<String> arguments = const [],
    String? workingDirectory,
    Duration? timeout,
    CommandPriority priority = CommandPriority.normal,
  }) async {
    final id = _log.startCommand([command, ...arguments].join(' '));
    try {
      final result = await _inner.run(
        command,
        arguments: arguments,
        workingDirectory: workingDirectory,
        timeout: timeout,
        priority: priority,
      );
      final stderr = result.stderr.trim();
      _log.endCommand(
        id,
        result.success
            ? 'ok'
            : 'exit ${result.exitCode}${stderr.isEmpty ? '' : ': ${_clip(stderr)}'}',
        error: !result.success,
      );
      return result;
    } catch (e) {
      _log.endCommand(id, 'threw ${_clip('$e')}', error: true);
      rethrow;
    }
  }
}

String _clip(String text, [int max = 200]) {
  final line = text.replaceAll('\n', ' ');
  return line.length <= max ? line : '${line.substring(0, max - 1)}…';
}
