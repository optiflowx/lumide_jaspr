import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/src/services/log_service.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class _InstalledVmBreakpoint {
  const _InstalledVmBreakpoint({
    required this.requested,
    this.vmBreakpoint,
    this.message,
  });

  final LumideDebugBreakpoint requested;
  final Breakpoint? vmBreakpoint;
  final String? message;
}

class _VariableReferenceEntry {
  const _VariableReferenceEntry({
    required this.value,
    required this.isolateId,
    this.evaluateName,
  });

  final dynamic value;
  final String? isolateId;
  final String? evaluateName;
}

class _DebugSessionRuntime {
  _DebugSessionRuntime({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  VmService? vmService;
  StreamSubscription<Event>? debugSub;
  StreamSubscription<Event>? loggingSub;
  String? activeIsolateId;
  String? wsUri;
  String? appId;
  bool connecting = false;
  bool didReceiveInitialBreakpointRequest = false;
  bool breakpointsSyncedForActiveIsolate = false;
  LumideDebugSessionState state = LumideDebugSessionState.launching;
  String? stoppedReason;
  String? statusMessage;
  int? activeFrameId;
  LumideDebugExceptionPauseMode exceptionPauseMode =
      LumideDebugExceptionPauseMode.unhandled;
  List<LumideDebugBreakpoint> requestedBreakpoints = const [];
  Map<String, _InstalledVmBreakpoint> installedBreakpointsByKey = {};
  final Map<int, Frame> framesById = {};
  final Map<int, List<BoundVariable>> variablesByFrameId = {};
  final Map<int, _VariableReferenceEntry> variableReferencesById = {};
  int nextVariableReference = 1;

  void clearFrameCache() {
    framesById.clear();
    variablesByFrameId.clear();
    variableReferencesById.clear();
    nextVariableReference = 1;
  }
}

/// Multi-session Dart VM debug bridge used for Jaspr Server + Client attach.
class DebugSessionService {
  DebugSessionService(this.context, this.logService);

  final LumideContext context;
  final LogService logService;

  static const LumideDebugCapabilities _capabilities = LumideDebugCapabilities(
    canContinue: true,
    canPause: true,
    canStepOver: true,
    canStepInto: true,
    canStepOut: true,
    canStop: true,
    canSetBreakpoints: true,
    canEvaluate: true,
  );

  final Map<String, _DebugSessionRuntime> _sessions = {};
  String? _outputChannelId;
  Future<void> Function()? onStopRequested;

  bool get hasSessions => _sessions.isNotEmpty;

  Future<void> init({String? outputChannelId}) async {
    _outputChannelId = outputChannelId;

    context.debug.onContinue(_handleContinue);
    context.debug.onPause(_handlePause);
    context.debug.onStepOver(_handleStepOver);
    context.debug.onStepInto(_handleStepInto);
    context.debug.onStepOut(_handleStepOut);
    context.debug.onStop(_handleStop);
    context.debug.onSetBreakpoints(_handleSetBreakpoints);
    context.debug.onSetExceptionPauseMode(_handleSetExceptionPauseMode);
    context.debug.onGetStackFrames(_handleGetStackFrames);
    context.debug.onGetScopes(_handleGetScopes);
    context.debug.onGetVariables(_handleGetVariables);
    context.debug.onEvaluate(_handleEvaluate);
  }

  void setOutputChannelId(String? id) {
    _outputChannelId = id;
  }

  Future<void> attachSession({
    required String sessionId,
    required String name,
    required String wsUri,
    String? appId,
  }) async {
    if (_sessions.containsKey(sessionId)) {
      logService.warn('Debug session $sessionId already exists');
      return;
    }

    final runtime = _DebugSessionRuntime(id: sessionId, name: name)
      ..wsUri = wsUri
      ..appId = appId
      ..statusMessage = 'Connecting to VM Service...';

    _sessions[sessionId] = runtime;

    await context.debug.startSession(
      LumideDebugSession(
        id: sessionId,
        name: name,
        state: LumideDebugSessionState.launching,
        capabilities: _capabilities,
        outputChannelId: _outputChannelId,
        statusMessage: runtime.statusMessage,
        exceptionPauseMode: runtime.exceptionPauseMode,
      ),
    );

    await _connectVm(runtime);
  }

  Future<void> endSession(String sessionId, {String? statusMessage}) async {
    final runtime = _sessions.remove(sessionId);
    if (runtime == null) return;

    if (statusMessage != null) {
      runtime
        ..state = LumideDebugSessionState.terminated
        ..statusMessage = statusMessage;
      await _pushSession(runtime);
    }

    await _disconnectVm(runtime);
    await context.debug.endSession(sessionId);
  }

  Future<void> endSessionByAppId(String appId) async {
    final match = _sessions.values.where((s) => s.appId == appId).toList();
    for (final runtime in match) {
      await endSession(runtime.id, statusMessage: 'Client stopped');
    }
  }

  Future<void> endAll({String? statusMessage}) async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      await endSession(id, statusMessage: statusMessage);
    }
  }

  Future<void> _connectVm(_DebugSessionRuntime runtime) async {
    if (runtime.connecting || runtime.vmService != null) return;
    runtime.connecting = true;

    try {
      final wsUri = runtime.wsUri;
      if (wsUri == null) return;

      logService.info('Connecting VM Service for ${runtime.name}: $wsUri');
      final service = await vmServiceConnectUri(wsUri);
      runtime.vmService = service;

      await service.streamListen(EventStreams.kDebug);
      await service.streamListen(EventStreams.kLogging);

      runtime.debugSub = service.onDebugEvent.listen((event) {
        unawaited(_handleVmDebugEvent(runtime, event));
      });
      runtime.loggingSub = service.onLoggingEvent.listen((event) {
        final record = event.logRecord;
        if (record == null) return;
        final message = record.message?.valueAsString ?? '';
        if (message.isNotEmpty) {
          logService.info('[${runtime.name}] $message');
        }
      });

      await _refreshActiveIsolate(runtime);

      runtime
        ..state = LumideDebugSessionState.running
        ..statusMessage = 'Attached';
      await _pushSession(runtime);
    } catch (e, st) {
      logService.error('Failed to connect VM for ${runtime.name}', e, st);
      runtime
        ..state = LumideDebugSessionState.terminated
        ..statusMessage = 'Attach failed: $e';
      await _pushSession(runtime);
      await endSession(runtime.id);
    } finally {
      runtime.connecting = false;
    }
  }

  Future<void> _disconnectVm(_DebugSessionRuntime runtime) async {
    await runtime.debugSub?.cancel();
    await runtime.loggingSub?.cancel();
    runtime.debugSub = null;
    runtime.loggingSub = null;
    try {
      await runtime.vmService?.dispose();
    } catch (_) {}
    runtime.vmService = null;
    runtime.clearFrameCache();
  }

  Future<void> _refreshActiveIsolate(_DebugSessionRuntime runtime) async {
    final service = runtime.vmService;
    if (service == null) return;

    try {
      final vm = await service.getVM();
      final isolates = vm.isolates ?? const [];
      if (isolates.isEmpty) return;

      final isolateRef = isolates.firstWhere(
        (ref) => ref.name?.contains('main') == true,
        orElse: () => isolates.first,
      );
      final isolateId = isolateRef.id;
      if (isolateId == null) return;

      await _setActiveIsolate(runtime, isolateId);

      final isolate = await service.getIsolate(isolateId);
      await _syncDebugStateFromPauseEvent(runtime, isolate.pauseEvent);
    } catch (e) {
      logService.error('Failed to determine active isolate', e);
    }
  }

  Future<void> _setActiveIsolate(
    _DebugSessionRuntime runtime,
    String isolateId,
  ) async {
    if (runtime.activeIsolateId == isolateId) return;

    runtime
      ..activeIsolateId = isolateId
      ..breakpointsSyncedForActiveIsolate = false
      ..installedBreakpointsByKey = {}
      ..clearFrameCache();

    final service = runtime.vmService;
    if (service == null) return;

    try {
      await service.setIsolatePauseMode(
        isolateId,
        exceptionPauseMode: _vmExceptionPauseModeFor(runtime.exceptionPauseMode),
      );
    } catch (e) {
      logService.error('Failed to configure isolate pause mode', e);
    }

    if (!runtime.didReceiveInitialBreakpointRequest) return;
    await _syncBreakpoints(runtime);
    await _pushBreakpoints(runtime);
  }

  Future<void> _handleVmDebugEvent(
    _DebugSessionRuntime runtime,
    Event event,
  ) async {
    final kind = event.kind;
    if (kind == null) return;

    final isolateId = event.isolate?.id;
    if (isolateId != null && isolateId != runtime.activeIsolateId) {
      await _setActiveIsolate(runtime, isolateId);
    }

    if (kind == EventKind.kPauseBreakpoint ||
        kind == EventKind.kPauseException ||
        kind == EventKind.kPauseInterrupted ||
        kind == EventKind.kPauseStart) {
      await _syncDebugStateFromPauseEvent(runtime, event);
      return;
    }

    if (kind == EventKind.kResume) {
      runtime
        ..state = LumideDebugSessionState.running
        ..stoppedReason = null
        ..activeFrameId = null
        ..clearFrameCache();
      await _pushSession(runtime);
      return;
    }

    if (kind == EventKind.kIsolateExit) {
      if (event.isolate?.id == runtime.activeIsolateId) {
        runtime.activeIsolateId = null;
      }
    }
  }

  Future<void> _syncDebugStateFromPauseEvent(
    _DebugSessionRuntime runtime,
    Event? event,
  ) async {
    if (event == null) return;
    final kind = event.kind;
    if (kind == null) return;
    if (kind != EventKind.kPauseBreakpoint &&
        kind != EventKind.kPauseException &&
        kind != EventKind.kPauseInterrupted &&
        kind != EventKind.kPauseStart) {
      return;
    }

    runtime
      ..state = LumideDebugSessionState.paused
      ..stoppedReason = kind
      ..clearFrameCache();

    try {
      final frames = await _loadStackFrames(runtime);
      if (frames.isNotEmpty) {
        runtime.activeFrameId = frames.first.id;
      }
    } catch (_) {}

    await _pushSession(runtime);
  }

  Future<void> _pushSession(_DebugSessionRuntime runtime) async {
    await context.debug.updateSession(
      LumideDebugSession(
        id: runtime.id,
        name: runtime.name,
        state: runtime.state,
        capabilities: _capabilities,
        outputChannelId: _outputChannelId,
        stoppedReason: runtime.stoppedReason,
        statusMessage: runtime.statusMessage,
        activeFrameId: runtime.activeFrameId,
        exceptionPauseMode: runtime.exceptionPauseMode,
      ),
    );
  }

  Future<void> _handleContinue(String sessionId) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) return;
    await service.resume(isolateId);
  }

  Future<void> _handlePause(String sessionId) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) return;
    await service.pause(isolateId);
  }

  Future<void> _handleStepOver(String sessionId) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) return;
    await service.resume(isolateId, step: StepOption.kOver);
  }

  Future<void> _handleStepInto(String sessionId) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) return;
    await service.resume(isolateId, step: StepOption.kInto);
  }

  Future<void> _handleStepOut(String sessionId) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) return;
    await service.resume(isolateId, step: StepOption.kOut);
  }

  Future<void> _handleStop(String sessionId) async {
    if (!_sessions.containsKey(sessionId)) return;
    final callback = onStopRequested;
    if (callback != null) {
      // Launch/debug Stop from the host should terminate the whole daemon,
      // not prompt again (confirm is for palette/status-bar Stop).
      await callback();
    } else {
      await endSession(sessionId, statusMessage: 'Stopped');
    }
  }

  Future<void> _handleSetBreakpoints(
    String sessionId,
    List<LumideDebugBreakpoint> breakpoints,
  ) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;

    runtime
      ..requestedBreakpoints = _normalizeBreakpoints(breakpoints)
      ..didReceiveInitialBreakpointRequest = true;

    await _syncBreakpoints(runtime);
    await _pushBreakpoints(runtime);
  }

  Future<void> _handleSetExceptionPauseMode(
    String sessionId,
    LumideDebugExceptionPauseMode mode,
  ) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return;

    runtime.exceptionPauseMode = mode;
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service != null && isolateId != null) {
      try {
        await service.setIsolatePauseMode(
          isolateId,
          exceptionPauseMode: _vmExceptionPauseModeFor(mode),
        );
      } catch (e) {
        logService.error('Failed to update isolate pause mode', e);
      }
    }
    await _pushSession(runtime);
  }

  Future<List<LumideDebugStackFrame>> _handleGetStackFrames(
    String sessionId,
  ) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return const [];
    return _loadStackFrames(runtime);
  }

  Future<List<LumideDebugScope>> _handleGetScopes(
    String sessionId,
    int frameId,
  ) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return const [];

    final frame = runtime.framesById[frameId];
    if (frame == null) return const [];

    final vars = frame.vars ?? const <BoundVariable>[];
    runtime.variablesByFrameId[frameId] = vars;

    return [
      LumideDebugScope(
        id: frameId,
        name: 'Locals',
      ),
    ];
  }

  Future<List<LumideDebugVariable>> _handleGetVariables(
    String sessionId,
    int variablesReference,
  ) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return const [];

    if (runtime.variablesByFrameId.containsKey(variablesReference)) {
      final locals = runtime.variablesByFrameId[variablesReference]!;
      final result = <LumideDebugVariable>[];
      for (final local in locals) {
        result.add(await _boundVariableToDebugVariable(runtime, local));
      }
      return result;
    }

    final entry = runtime.variableReferencesById[variablesReference];
    if (entry == null) return const [];
    return _expandVariableReference(runtime, entry);
  }

  Future<LumideDebugEvaluationResult?> _handleEvaluate(
    String sessionId,
    String expression, {
    int? frameId,
  }) async {
    final runtime = _sessions[sessionId];
    if (runtime == null) return null;

    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) {
      return const LumideDebugEvaluationResult(
        result: 'No active isolate',
        type: 'error',
      );
    }

    try {
      final targetId = frameId != null
          ? runtime.framesById[frameId]?.code?.id
          : null;
      final response = await service.evaluate(
        isolateId,
        targetId ?? isolateId,
        expression,
        disableBreakpoints: true,
      );

      return switch (response) {
        InstanceRef instanceRef => LumideDebugEvaluationResult(
            result: instanceRef.valueAsString ??
                instanceRef.classRef?.name ??
                instanceRef.kind ??
                'null',
            type: instanceRef.classRef?.name,
          ),
        ErrorRef errorRef => LumideDebugEvaluationResult(
            result: errorRef.message ?? 'Evaluation failed',
            type: errorRef.kind,
          ),
        _ => LumideDebugEvaluationResult(result: response.toString()),
      };
    } catch (e) {
      return LumideDebugEvaluationResult(
        result: 'Evaluation failed: $e',
        type: 'error',
      );
    }
  }

  Future<List<LumideDebugStackFrame>> _loadStackFrames(
    _DebugSessionRuntime runtime,
  ) async {
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) return const [];

    final stack = await service.getStack(isolateId);
    final frames = stack.frames ?? const [];
    runtime.clearFrameCache();

    final result = <LumideDebugStackFrame>[];
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final id = i + 1;
      runtime.framesById[id] = frame;

      final location = frame.location;
      final scriptUri = location?.script?.uri;
      result.add(
        LumideDebugStackFrame(
          id: id,
          name: frame.code?.name ?? frame.kind ?? 'frame',
          sourceUri: scriptUri ?? '',
          line: location?.line ?? 0,
          column: location?.column ?? 0,
        ),
      );
    }
    return result;
  }

  Future<LumideDebugVariable> _boundVariableToDebugVariable(
    _DebugSessionRuntime runtime,
    BoundVariable local,
  ) async {
    final value = local.value;
    final name = local.name ?? 'var';

    if (value is InstanceRef) {
      final expandable = value.valueAsString == null &&
          (value.kind == InstanceKind.kPlainInstance ||
              value.kind == InstanceKind.kList ||
              value.kind == InstanceKind.kMap ||
              value.kind == InstanceKind.kRecord ||
              value.kind == InstanceKind.kSet);
      final refId = expandable
          ? _storeVariableRef(runtime, value, runtime.activeIsolateId)
          : null;

      return LumideDebugVariable(
        name: name,
        value: value.valueAsString ??
            value.classRef?.name ??
            value.kind ??
            'Instance',
        type: value.classRef?.name ?? value.kind,
        variablesReference: refId,
      );
    }

    return LumideDebugVariable(
      name: name,
      value: value?.toString() ?? 'null',
      type: value?.runtimeType.toString(),
    );
  }

  int? _storeVariableRef(
    _DebugSessionRuntime runtime,
    dynamic value,
    String? isolateId, {
    String? evaluateName,
  }) {
    final id = runtime.nextVariableReference++;
    runtime.variableReferencesById[id] = _VariableReferenceEntry(
      value: value,
      isolateId: isolateId,
      evaluateName: evaluateName,
    );
    return id;
  }

  Future<List<LumideDebugVariable>> _expandVariableReference(
    _DebugSessionRuntime runtime,
    _VariableReferenceEntry entry,
  ) async {
    final service = runtime.vmService;
    final isolateId = entry.isolateId ?? runtime.activeIsolateId;
    if (service == null || isolateId == null) return const [];

    final value = entry.value;
    if (value is! InstanceRef || value.id == null) return const [];

    try {
      final instance = await service.getObject(isolateId, value.id!);
      if (instance is! Instance) return const [];

      final result = <LumideDebugVariable>[];
      final fields = instance.fields ?? const [];
      for (final field in fields) {
        final name = field.decl?.name ?? field.name ?? 'field';
        final fieldValue = field.value;
        if (fieldValue is InstanceRef) {
          result.add(
            LumideDebugVariable(
              name: name,
              value: fieldValue.valueAsString ??
                  fieldValue.classRef?.name ??
                  'Instance',
              type: fieldValue.classRef?.name,
              variablesReference: fieldValue.valueAsString == null
                  ? _storeVariableRef(runtime, fieldValue, isolateId)
                  : null,
            ),
          );
        } else {
          result.add(
            LumideDebugVariable(
              name: name,
              value: fieldValue?.toString() ?? 'null',
            ),
          );
        }
      }
      return result;
    } catch (e) {
      logService.error('Failed to expand variable', e);
      return const [];
    }
  }

  Future<void> _syncBreakpoints(_DebugSessionRuntime runtime) async {
    final service = runtime.vmService;
    final isolateId = runtime.activeIsolateId;
    if (service == null || isolateId == null) {
      runtime.breakpointsSyncedForActiveIsolate = false;
      return;
    }

    final desired = <String, LumideDebugBreakpoint>{
      for (final bp in runtime.requestedBreakpoints)
        if (bp.enabled) _breakpointKey(bp): bp,
    };

    final stale = runtime.installedBreakpointsByKey.keys
        .where((key) => !desired.containsKey(key))
        .toList();

    for (final key in stale) {
      final installed = runtime.installedBreakpointsByKey.remove(key);
      final id = installed?.vmBreakpoint?.id;
      if (id == null) continue;
      try {
        await service.removeBreakpoint(isolateId, id);
      } catch (e) {
        logService.error('Failed to remove breakpoint', e);
      }
    }

    for (final entry in desired.entries) {
      final existing = runtime.installedBreakpointsByKey[entry.key];
      if (existing?.vmBreakpoint != null) continue;

      try {
        final vmBp = await _addBreakpoint(
          service: service,
          isolateId: isolateId,
          breakpoint: entry.value,
        );
        runtime.installedBreakpointsByKey[entry.key] = _InstalledVmBreakpoint(
          requested: entry.value,
          vmBreakpoint: vmBp,
        );
      } catch (e) {
        runtime.installedBreakpointsByKey[entry.key] = _InstalledVmBreakpoint(
          requested: entry.value,
          message: e.toString(),
        );
      }
    }

    runtime.breakpointsSyncedForActiveIsolate = true;
  }

  Future<Breakpoint> _addBreakpoint({
    required VmService service,
    required String isolateId,
    required LumideDebugBreakpoint breakpoint,
  }) async {
    final candidates = [breakpoint.sourceUri];
    final parsed = Uri.tryParse(breakpoint.sourceUri);
    if (parsed != null && parsed.scheme == 'file') {
      try {
        final packageUris = await service.lookupPackageUris(
          isolateId,
          [breakpoint.sourceUri],
        );
        final uris = packageUris.uris;
        final packageUri = uris != null && uris.isNotEmpty ? uris.first : null;
        if (packageUri != null && packageUri.isNotEmpty) {
          candidates.add(packageUri);
        }
      } catch (_) {}
    }

    Object? lastError;
    for (final uri in candidates) {
      try {
        return await service.addBreakpointWithScriptUri(
          isolateId,
          uri,
          breakpoint.line,
          column: breakpoint.column,
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('Failed to add breakpoint');
  }

  Future<void> _pushBreakpoints(_DebugSessionRuntime runtime) async {
    final breakpoints = runtime.requestedBreakpoints.map((bp) {
      final installed = runtime.installedBreakpointsByKey[_breakpointKey(bp)];
      return LumideDebugBreakpoint(
        id: installed?.vmBreakpoint?.id ?? bp.id,
        sourceUri: bp.sourceUri,
        line: bp.line,
        column: bp.column,
        endLine: bp.endLine,
        endColumn: bp.endColumn,
        condition: bp.condition,
        enabled: bp.enabled,
        verified: installed?.vmBreakpoint?.resolved ?? false,
        message: installed?.message,
      );
    }).toList(growable: false);

    await context.debug.updateBreakpoints(runtime.id, breakpoints);
  }

  String _vmExceptionPauseModeFor(LumideDebugExceptionPauseMode mode) {
    return switch (mode) {
      LumideDebugExceptionPauseMode.none => ExceptionPauseMode.kNone,
      LumideDebugExceptionPauseMode.unhandled => ExceptionPauseMode.kUnhandled,
      LumideDebugExceptionPauseMode.all => ExceptionPauseMode.kAll,
    };
  }

  String _breakpointKey(LumideDebugBreakpoint bp) {
    return '${bp.sourceUri}:${bp.line}:${bp.column ?? 0}';
  }

  List<LumideDebugBreakpoint> _normalizeBreakpoints(
    List<LumideDebugBreakpoint> breakpoints,
  ) {
    final deduped = <String, LumideDebugBreakpoint>{};
    for (final bp in breakpoints) {
      deduped[_breakpointKey(bp)] = bp;
    }
    return List.unmodifiable(deduped.values);
  }

  Future<void> dispose() async {
    await endAll(statusMessage: 'Disposed');
  }
}
