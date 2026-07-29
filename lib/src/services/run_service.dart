import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/src/constants.dart';
import 'package:lumide_jaspr/src/services/debug_session_service.dart';
import 'package:lumide_jaspr/src/services/jaspr_service.dart';
import 'package:lumide_jaspr/src/services/launch_source_resolver.dart';
import 'package:lumide_jaspr/src/services/log_service.dart';
import 'package:lumide_jaspr/src/services/project_service.dart';
import 'package:lumide_jaspr/src/services/serve_daemon_service.dart';
import 'package:lumide_jaspr/src/services/status_bar_service.dart';
import 'package:path/path.dart' as path;

enum _JasprLaunchMode { run, debug }

class RunService {
  RunService({
    required this.context,
    required this.projectService,
    required this.jasprService,
    required this.daemonService,
    required this.debugSessionService,
    required this.statusBarService,
    required this.logService,
  });

  final LumideContext context;
  final ProjectService projectService;
  final JasprService jasprService;
  final ServeDaemonService daemonService;
  final DebugSessionService debugSessionService;
  final StatusBarService statusBarService;
  final LogService logService;

  LumideOutputChannel? _channel;
  LumideOutputChannel? get channel => _channel;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  _JasprLaunchMode? _launchMode;
  LumideLaunchKind? _activeLaunchKind;
  String? _activeLaunchConfigurationId;
  String? _runName;
  int _runId = 0;

  Future<void> init() async {
    final logLimit =
        await context.workspace.getConfiguration(confLogEntryLimit) as int? ??
        defaultLogEntryLimit;

    _channel = await context.window.createOutputChannel(
      channelJaspr,
      maxEntries: logLimit,
    );

    debugSessionService.setOutputChannelId(_channel?.id);
    await debugSessionService.init(outputChannelId: _channel?.id);
    debugSessionService.onStopRequested = () => stop(confirm: false);

    daemonService.onEvent = _handleDaemonEvent;
    daemonService.onExit = _handleDaemonExit;

    context.launch.onResolveConfigurations(_resolveLaunchConfigurations);
    context.launch.onResolveConfiguration(_resolveSourceConfiguration);
    context.launch.onImportConfiguration(importVscodeJasprLaunch);
    context.launch.onConfigure(_handleConfigureRequest);
    context.launch.onLaunch(_handleLaunchRequest);

    final initialConfigs = await _currentLaunchConfigurations();
    await context.launch.registerProvider(
      id: launchProviderJaspr,
      title: 'Jaspr',
      workspacePatterns: const ['pubspec.yaml'],
      kinds: const [
        LumideLaunchKind.run,
        LumideLaunchKind.debug,
      ],
      defaultKinds: const [
        LumideLaunchKind.run,
        LumideLaunchKind.debug,
      ],
      icon: iconGlobe,
      configurationSchema: 'schemas/launch.schema.json',
      configurationSnippets: const [
        {
          'name': 'Jaspr',
          'kinds': ['run', 'debug'],
          'config': {},
        },
        {
          'name': 'Jaspr (release)',
          'kinds': ['run', 'debug'],
          'config': {
            'args': ['--release'],
          },
        },
      ],
      configurationImports: const [
        LumideLaunchImportDescriptor(
          format: 'vscode',
          selectors: {
            'type': ['jaspr'],
          },
        ),
      ],
      priority: 90,
    );

    await context.launch.updateConfigurations(
      launchProviderJaspr,
      initialConfigs,
    );

    context.toolbar.onTap((id, position) {
      switch (id) {
        case cmdJasprServe:
          unawaited(serve());
        case cmdJasprDebug:
          unawaited(debug());
        case cmdJasprStop:
          unawaited(stop());
      }
    });
  }

  Future<List<LumideLaunchConfiguration>> _currentLaunchConfigurations() async {
    final projects = await projectService.findAllJasprProjects();
    if (projects.isEmpty) {
      return [
        const LumideLaunchConfiguration(
          id: launchConfigCurrent,
          label: 'Jaspr',
          kinds: [LumideLaunchKind.run, LumideLaunchKind.debug],
          arguments: {'canLaunch': true},
        ),
      ];
    }

    return [
      for (final project in projects)
        LumideLaunchConfiguration(
          id: 'jaspr:${path.basename(project)}',
          label: path.basename(project),
          kinds: const [LumideLaunchKind.run, LumideLaunchKind.debug],
          description: project,
          icon: iconGlobe,
          arguments: {
            'canLaunch': true,
            'cwd': project,
            'targetLabel': path.basename(project),
            'targetTooltip': project,
          },
        ),
      const LumideLaunchConfiguration(
        id: 'jaspr.release',
        label: 'Jaspr (release)',
        kinds: [LumideLaunchKind.run, LumideLaunchKind.debug],
        icon: iconGlobe,
        arguments: {
          'canLaunch': true,
          'args': ['--release'],
        },
      ),
    ];
  }

  Future<void> refreshLaunchConfigurations() async {
    final configs = await _currentLaunchConfigurations();
    await context.launch.updateConfigurations(launchProviderJaspr, configs);
  }

  Future<List<LumideLaunchConfiguration>> _resolveLaunchConfigurations(
    LumideLaunchResolveRequest request,
  ) async {
    if (request.providerId != launchProviderJaspr) return const [];
    return _currentLaunchConfigurations();
  }

  Future<LumideLaunchResolution> _resolveSourceConfiguration(
    LumideLaunchSourceConfiguration source,
  ) async {
    final root = await projectService.getProjectRoot();
    return resolveJasprLaunchSource(source, projectRoot: root);
  }

  Future<LumideLaunchConfiguration?> _handleConfigureRequest(
    LumideLaunchConfigureRequest request,
  ) async {
    if (request.providerId != launchProviderJaspr) return null;

    // Host launch toolbar Stop button arrives as actionId: 'stop'
    // (same pattern as lumide_flutter).
    switch (request.actionId) {
      case 'stop':
        await stop();
        return request.configuration;
      default:
        return request.configuration;
    }
  }

  Future<void> _handleLaunchRequest(LumideLaunchRequest request) async {
    final kind = request.kind;
    final debugMode = kind == LumideLaunchKind.debug;
    await _start(
      mode: debugMode ? _JasprLaunchMode.debug : _JasprLaunchMode.run,
      configuration: request.configuration,
      launchKind: kind,
    );
  }

  Future<void> serve() async {
    await _start(mode: _JasprLaunchMode.run);
  }

  Future<void> debug() async {
    await _start(mode: _JasprLaunchMode.debug);
  }

  Future<void> _start({
    required _JasprLaunchMode mode,
    LumideLaunchConfiguration? configuration,
    LumideLaunchKind? launchKind,
  }) async {
    if (_isRunning) {
      await context.window.showMessage(
        'Jaspr is already running. Stop it first.',
        type: MessageType.warning,
      );
      return;
    }

    if (!await jasprService.ensureCliReady()) return;

    String cwd;
    List<String> args = const [];
    Map<String, String> env = const {};

    if (configuration != null) {
      final arguments = configuration.arguments;
      cwd =
          arguments['cwd']?.toString() ?? await projectService.getProjectRoot();
      if (arguments['args'] case final List rawArgs) {
        args = rawArgs.map((e) => e.toString()).toList();
      }
      if (arguments['env'] case final Map rawEnv) {
        env = rawEnv.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }
      _activeLaunchConfigurationId = configuration.id;
      _runName = configuration.label;
    } else {
      final projects = await projectService.findAllJasprProjects();
      if (projects.isEmpty) {
        try {
          cwd = await projectService.getProjectRoot();
        } catch (e) {
          await context.window.showMessage(
            'No Jaspr project found in the workspace.',
            type: MessageType.error,
          );
          return;
        }
        if (!await projectService.isJasprProject(cwd)) {
          await context.window.showMessage(
            'The current project does not appear to be a Jaspr project.',
            type: MessageType.error,
          );
          return;
        }
      } else if (projects.length == 1) {
        cwd = projects.first;
      } else {
        final picked = await context.window.showQuickPick(
          [
            for (final p in projects)
              QuickPickItem(label: path.basename(p), payload: p, detail: p),
          ],
          placeholder: 'Select Jaspr project to serve',
        );
        if (picked?.payload == null) return;
        cwd = picked!.payload.toString();
      }
      _runName = 'Jaspr';
    }

    if (!path.isAbsolute(cwd)) {
      final root = await projectService.getWorkspaceRoot();
      cwd = path.normalize(path.join(root, cwd));
    }

    _launchMode = mode;
    _activeLaunchKind =
        launchKind ??
        (mode == _JasprLaunchMode.debug
            ? LumideLaunchKind.debug
            : LumideLaunchKind.run);
    _runId = DateTime.now().millisecondsSinceEpoch;
    _isRunning = true;

    await _channel?.clear();
    await _channel?.show();
    await _channel?.appendLine(
      'Starting Jaspr ${_launchMode == _JasprLaunchMode.debug ? 'debug' : 'serve'} in $cwd',
    );

    await statusBarService.setStarting();

    final event = LumideLaunchEvent(
      providerId: launchProviderJaspr,
      kind: _activeLaunchKind!,
      configurationId: _activeLaunchConfigurationId ?? launchConfigCurrent,
    );
    await context.launch.didStart(event);

    try {
      await daemonService.start(
        workingDirectory: cwd,
        args: args,
        environment: env.isEmpty ? null : env,
      );
    } catch (e, st) {
      logService.error('Failed to start jaspr daemon', e, st);
      await _channel?.appendLine('Failed to start: $e');
      await statusBarService.setFailed();
      _isRunning = false;
      await context.launch.didEnd(event);
      await context.window.showMessage(
        'Failed to start Jaspr: $e',
        type: MessageType.error,
      );
    }
  }

  Future<void> _handleDaemonEvent(JasprDaemonEvent event) async {
    switch (event.name) {
      case 'daemon.log':
        final message = event.params['message']?.toString() ?? '';
        final cleaned = message.replaceAll(r'\033', '\x1b');
        await _channel?.appendLine(cleaned);
      case 'server.started':
        await statusBarService.setRunning();
        await _maybeRegisterToolbar();
        if (_launchMode == _JasprLaunchMode.debug) {
          final uri = event.params['vmServiceUri']?.toString();
          if (uri != null && uri.isNotEmpty) {
            await debugSessionService.attachSession(
              sessionId: 'jaspr.server.$_runId',
              name: 'Server | ${_runName ?? 'Jaspr'}',
              wsUri: uri,
            );
          }
        }
      case 'client.debugPort':
        await statusBarService.setRunning();
        if (_launchMode == _JasprLaunchMode.debug) {
          final uri = event.params['wsUri']?.toString();
          final appId = event.params['appId']?.toString();
          if (uri != null && uri.isNotEmpty) {
            await debugSessionService.attachSession(
              sessionId: 'jaspr.client.$_runId.${appId ?? '0'}',
              name: 'Client | ${_runName ?? 'Jaspr'}',
              wsUri: uri,
              appId: appId,
            );
          }
        }
      case 'client.stop':
        final appId = event.params['appId']?.toString();
        if (appId != null) {
          await debugSessionService.endSessionByAppId(appId);
        }
      default:
        logService.info('Unhandled daemon event: ${event.name}');
    }
  }

  Future<void> _handleDaemonExit(int? code) async {
    await debugSessionService.endAll(statusMessage: 'Jaspr stopped');
    await _unregisterToolbar();

    if (_isRunning) {
      await _channel?.appendLine(
        code == 0 || code == null
            ? 'Jaspr Serve exited successfully.'
            : 'Jaspr Serve exited with code $code.',
      );
    }

    final wasRunning = _isRunning;
    _isRunning = false;
    _launchMode = null;

    if (code != null && code != 0 && wasRunning) {
      await statusBarService.setFailed();
    } else {
      await statusBarService.setStopped();
    }

    if (_activeLaunchKind != null) {
      await context.launch.didEnd(
        LumideLaunchEvent(
          providerId: launchProviderJaspr,
          kind: _activeLaunchKind!,
          configurationId: _activeLaunchConfigurationId ?? launchConfigCurrent,
        ),
      );
    }
    _activeLaunchKind = null;
    _activeLaunchConfigurationId = null;
  }

  Future<void> stop({bool confirm = true}) async {
    if (!_isRunning && !daemonService.isRunning) {
      await context.window.showMessage(
        'No Jaspr process is running.',
        type: MessageType.warning,
      );
      return;
    }

    if (confirm) {
      final accepted = await context.window.showConfirmDialog(
        'Stop the running Jaspr server?',
        title: 'Stop Jaspr',
      );
      if (!accepted) return;
    }

    await _channel?.appendLine('Stopping Jaspr...');
    await debugSessionService.endAll(statusMessage: 'Stopped');
    await daemonService.shutdown();

    // If the process ignored shutdown, force-kill so the UI can recover.
    if (daemonService.isRunning) {
      await daemonService.kill();
    }
  }

  bool _toolbarRegistered = false;

  Future<void> _maybeRegisterToolbar() async {
    if (_toolbarRegistered) return;
    _toolbarRegistered = true;
    try {
      await context.toolbar.registerItem(
        id: cmdJasprStop,
        icon: iconStop,
        tooltip: 'Stop Jaspr',
        alignment: ToolbarItemAlignment.right,
        priority: 100,
      );
    } catch (_) {}
  }

  Future<void> _unregisterToolbar() async {
    if (!_toolbarRegistered) return;
    _toolbarRegistered = false;
    try {
      await context.toolbar.unregisterItem(cmdJasprStop);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await debugSessionService.dispose();
    await daemonService.dispose();
    await _channel?.dispose();
    _channel = null;
  }
}
