import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lumide_jaspr/src/services/log_service.dart';
import 'package:lumide_jaspr/src/services/sdk_manager.dart';

/// A parsed event from the Jaspr daemon JSON protocol.
class JasprDaemonEvent {
  const JasprDaemonEvent({
    required this.name,
    this.params = const {},
  });

  final String name;
  final Map<String, dynamic> params;

  factory JasprDaemonEvent.log(String message) {
    return JasprDaemonEvent(
      name: 'daemon.log',
      params: {'message': message},
    );
  }
}

/// Parses a single stdout/stderr line from `jaspr daemon`.
///
/// Lines that are JSON arrays like `[{event, params}]` become structured
/// events; everything else becomes a `daemon.log` event.
JasprDaemonEvent? parseDaemonLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('[{') && trimmed.endsWith('}]')) {
    try {
      final json = jsonDecode(trimmed);
      if (json is List && json.isNotEmpty) {
        final first = json.first;
        if (first is Map) {
          final map = Map<String, dynamic>.from(first);
          final eventName = map['event']?.toString();
          if (eventName != null && eventName.isNotEmpty) {
            final params = map['params'];
            return JasprDaemonEvent(
              name: eventName,
              params: params is Map
                  ? Map<String, dynamic>.from(params)
                  : const {},
            );
          }
        }
      }
    } catch (_) {}
  }

  return JasprDaemonEvent.log(trimmed);
}

typedef JasprDaemonEventHandler = Future<void> Function(JasprDaemonEvent event);

/// Spawns and manages a `jaspr daemon` process.
class ServeDaemonService {
  ServeDaemonService({
    required this.sdkManager,
    required this.logService,
  });

  final SdkManager sdkManager;
  final LogService logService;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  JasprDaemonEventHandler? onEvent;
  void Function(int? exitCode)? onExit;

  Future<void> start({
    required String workingDirectory,
    List<String> args = const [],
    Map<String, String>? environment,
  }) async {
    if (_isRunning) {
      throw StateError('Jaspr daemon is already running');
    }

    final cmd = await sdkManager.getJasprCommand();
    final processArgs = [...cmd.sublist(1), 'daemon', ...args];

    logService.info(
      'Starting: ${cmd.first} ${processArgs.join(' ')} (cwd: $workingDirectory)',
    );

    final process = await Process.start(
      cmd.first,
      processArgs,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );

    _process = process;
    _isRunning = true;

    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);

    unawaited(process.exitCode.then((code) async {
      _isRunning = false;
      await _cancelSubs();
      onExit?.call(code);
    }));
  }

  Future<void> _handleLine(String line) async {
    final event = parseDaemonLine(line);
    if (event == null) return;
    final handler = onEvent;
    if (handler != null) {
      await handler(event);
    }
  }

  /// Requests a graceful daemon shutdown.
  Future<void> shutdown({Duration timeout = const Duration(seconds: 5)}) async {
    final process = _process;
    if (process == null) return;

    try {
      process.stdin.writeln('[{"method":"daemon.shutdown","id":"0"}]');
      await process.stdin.flush();
    } catch (e) {
      logService.warn('Failed to write daemon.shutdown: $e');
    }

    try {
      await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }

    await _cleanup();
  }

  Future<void> kill() async {
    final process = _process;
    if (process == null) return;
    process.kill(ProcessSignal.sigkill);
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _isRunning = false;
    await _cancelSubs();
    _process = null;
  }

  Future<void> _cancelSubs() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
  }

  Future<void> dispose() async {
    if (_isRunning) {
      await shutdown();
    }
    await _cleanup();
  }
}
