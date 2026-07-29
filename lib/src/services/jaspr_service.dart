import 'dart:io';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/src/constants.dart';
import 'package:lumide_jaspr/src/services/log_service.dart';
import 'package:lumide_jaspr/src/services/project_service.dart';
import 'package:lumide_jaspr/src/services/sdk_manager.dart';
import 'package:lumide_jaspr/src/services/status_bar_service.dart';
import 'package:path/path.dart' as path;

/// Options passed to `jaspr create`.
class JasprCreateOptions {
  const JasprCreateOptions({
    this.mode,
    this.routing,
    this.flutter,
    this.backend,
    this.template,
  });

  final String? mode;
  final String? routing;
  final String? flutter;
  final String? backend;
  final String? template;

  bool get isClientMode => mode == 'client';
}

class JasprService {
  final LumideContext context;
  final ProjectService projectService;
  final SdkManager sdkManager;
  final StatusBarService statusBarService;
  final LogService logService;

  LumideOutputChannel? _toolsChannel;

  Future<void> Function()? onServe;
  Future<void> Function()? onDebug;
  Future<void> Function()? onStop;

  JasprService(
    this.context,
    this.projectService,
    this.sdkManager,
    this.statusBarService,
    this.logService,
  );

  Future<void> dispose() async {
    await _toolsChannel?.dispose();
    _toolsChannel = null;
  }

  Future<LumideOutputChannel> _channel() async {
    return _toolsChannel ??=
        await context.window.createOutputChannel('Jaspr Tools');
  }

  Future<bool> ensureCliReady() async {
    final version = await sdkManager.getJasprVersion();
    if (version == null) {
      final choice = await context.window.showQuickPick(
        [
          const QuickPickItem(label: 'Install Now', payload: 'install'),
          const QuickPickItem(label: 'Cancel', payload: 'cancel'),
        ],
        placeholder:
            'jaspr_cli is not installed. Install via dart pub global activate?',
      );
      if (choice?.payload != 'install') return false;
      return _installCli();
    }

    if (compareSemver(version, minimumJasprVersion) < 0) {
      final choice = await context.window.showQuickPick(
        [
          const QuickPickItem(label: 'Update Now', payload: 'update'),
          const QuickPickItem(label: 'Cancel', payload: 'cancel'),
        ],
        placeholder:
            'jaspr_cli $version is too old. Update to $minimumJasprVersion+?',
      );
      if (choice?.payload != 'update') return false;
      return _installCli();
    }

    await statusBarService.updateVersion(version);
    return true;
  }

  Future<bool> _installCli() async {
    try {
      final dart = await sdkManager.getDartCommand();
      // Prefer modern `dart install`; fall back to pub global activate.
      var result = await context.shell.run(
        dart.first,
        [...dart.sublist(1), 'install', 'jaspr_cli'],
      );
      if (result.exitCode != 0) {
        result = await context.shell.run(
          dart.first,
          [
            ...dart.sublist(1),
            'pub',
            'global',
            'activate',
            'jaspr_cli',
          ],
        );
      }

      sdkManager.clearCache();
      final version = await sdkManager.getJasprVersion();
      if (version == null ||
          compareSemver(version, minimumJasprVersion) < 0) {
        await context.window.showMessage(
          'Failed to install jaspr_cli. Run `dart pub global activate jaspr_cli` manually.',
          type: MessageType.error,
        );
        return false;
      }
      await statusBarService.updateVersion(version);
      await context.window.showMessage('jaspr_cli $version installed.');
      return true;
    } catch (e) {
      await context.window.showMessage(
        'Failed to install jaspr_cli: $e',
        type: MessageType.error,
      );
      return false;
    }
  }

  Future<void> checkSdk() async {
    final version = await sdkManager.getJasprVersion();
    if (version == null) {
      await statusBarService.updateVersion('Not Found');
      return;
    }
    await statusBarService.updateVersion(version);
  }

  Future<void> doctor([String? projectRoot]) async {
    if (!await ensureCliReady()) return;
    final root = projectRoot ?? await projectService.getProjectRoot();
    await _runAndShow(['doctor'], root, alwaysShow: true);
  }

  Future<void> clean([String? projectRoot]) async {
    if (!await ensureCliReady()) return;
    final root = projectRoot ?? await projectService.getProjectRoot();
    await _runAndShow(['clean'], root);
  }

  Future<void> doctorForContext(Map<String, dynamic>? args) async {
    final root = await projectService.projectRootFromMenuContext(args);
    await doctor(root);
  }

  Future<void> cleanForContext(Map<String, dynamic>? args) async {
    final root = await projectService.projectRootFromMenuContext(args);
    await clean(root);
  }

  Future<void> createForContext(Map<String, dynamic>? args) async {
    final folder = projectService.folderFromMenuContext(args);
    await create(defaultParent: folder);
  }

  Future<void> showToolsMenu([Map<String, dynamic>? args]) async {
    final choice = await context.window.showQuickPick(
      [
        const QuickPickItem(label: 'Serve', payload: 'serve'),
        const QuickPickItem(label: 'Debug', payload: 'debug'),
        const QuickPickItem(label: 'Stop', payload: 'stop'),
        const QuickPickItem(label: 'New Project', payload: 'create'),
        const QuickPickItem(label: 'Doctor', payload: 'doctor'),
        const QuickPickItem(label: 'Clean', payload: 'clean'),
      ],
      placeholder: 'Jaspr Tools',
    );

    switch (choice?.payload?.toString()) {
      case 'serve':
        await onServe?.call();
      case 'debug':
        await onDebug?.call();
      case 'stop':
        await onStop?.call();
      case 'create':
        await create();
      case 'doctor':
        await doctor();
      case 'clean':
        await clean();
    }
  }

  Future<void> create({String? defaultParent}) async {
    if (!await ensureCliReady()) return;

    final version = await sdkManager.getJasprVersion() ?? minimumJasprVersion;
    final options = await _pickCreateOptions(version);
    if (options == null) return;

    final parent = defaultParent ??
        await context.window.showOpenFolderDialog(
          title: 'Select a folder to create the project in',
        );
    if (parent == null || parent.isEmpty) return;

    final name = await _promptProjectName(parent);
    if (name == null) return;

    final projectDir = path.join(parent, name);
    if (await context.fs.exists(projectDir)) {
      await context.window.showMessage(
        'A folder named "$name" already exists in $parent',
        type: MessageType.error,
      );
      return;
    }

    await context.fs.createDirectory(projectDir, recursive: true);

    final args = <String>['create'];
    if (options.template != null) {
      args.addAll(['--template', options.template!]);
    } else {
      args.addAll(['--mode', options.mode ?? 'static:auto']);
      args.addAll(['--routing', options.routing ?? 'none']);
      args.addAll(['--flutter', options.flutter ?? 'none']);
      if (options.mode == 'server' || options.mode == 'server:auto') {
        args.addAll(['--backend', options.backend ?? 'none']);
      }
    }
    args.add('.');

    final channel = await _channel();
    await channel.show();
    await channel.append('Creating Jaspr project in $projectDir...\n');

    final cmd = await sdkManager.getJasprCommand();
    final result = await context.shell.run(
      cmd.first,
      [...cmd.sublist(1), ...args],
      workingDirectory: projectDir,
    );

    await channel.append(result.stdout.toString());
    if (result.stderr.toString().trim().isNotEmpty) {
      await channel.append(result.stderr.toString());
    }

    if (result.exitCode != 0) {
      await context.window.showMessage(
        'jaspr create failed (exit ${result.exitCode})',
        type: MessageType.error,
      );
      return;
    }

    final entry = options.isClientMode
        ? path.join(projectDir, 'lib', 'main.client.dart')
        : path.join(projectDir, 'lib', 'main.server.dart');
    if (await context.fs.exists(entry)) {
      await context.editor.openDocument(Uri.file(entry).toString());
    }

    await context.window.showMessage(
      'Your Jaspr project is ready! Use Jaspr: Serve or Debug to start.',
    );
  }

  Future<JasprCreateOptions?> _pickCreateOptions(String version) async {
    final curated = <QuickPickItem>[
      if (compareSemver(version, '0.19.0') >= 0)
        const QuickPickItem(
          label: 'Documentation Site',
          description: 'using jaspr_content',
          detail:
              'A documentation site rendered from Markdown with prebuilt layout.',
          payload: 'docs',
        ),
      const QuickPickItem(
        label: 'Static Site',
        description: 'General Purpose (Recommended)',
        detail: 'Pre-rendered static site with routing and interactivity.',
        payload: 'static',
      ),
      const QuickPickItem(
        label: 'Server Rendered Site',
        description: 'General Purpose',
        detail: 'SSR site with routing and client-side interactivity.',
        payload: 'server',
      ),
      const QuickPickItem(
        label: 'Single Page Application',
        description: 'Dashboards, Admin Panels & More',
        detail: 'Client-mode SPA with client-side routing.',
        payload: 'client',
      ),
      const QuickPickItem(
        label: 'Embedded Flutter Site',
        description: 'Flutter App Showcase, Widget Demos & More',
        detail: 'Static site with an embedded Flutter app.',
        payload: 'embedded',
      ),
      const QuickPickItem(
        label: 'Custom Backend Site',
        description: 'Shelf Backend, API & More',
        detail: 'Server-rendered site with a shelf backend.',
        payload: 'backend',
      ),
      const QuickPickItem(
        label: 'More ...',
        payload: 'more',
      ),
    ];

    final selected = await context.window.showQuickPick(
      curated,
      placeholder: 'Select a starter template',
    );
    if (selected == null) return null;

    return switch (selected.payload?.toString()) {
      'docs' => const JasprCreateOptions(template: 'docs'),
      'static' => const JasprCreateOptions(
          mode: 'static:auto',
          routing: 'multi-page',
          flutter: 'plugins-only',
        ),
      'server' => const JasprCreateOptions(
          mode: 'server:auto',
          routing: 'multi-page',
          flutter: 'plugins-only',
        ),
      'client' => const JasprCreateOptions(
          mode: 'client',
          routing: 'single-page',
          flutter: 'plugins-only',
        ),
      'embedded' => const JasprCreateOptions(
          mode: 'static:auto',
          routing: 'multi-page',
          flutter: 'embedded',
        ),
      'backend' => const JasprCreateOptions(
          mode: 'server:auto',
          routing: 'multi-page',
          backend: 'shelf',
        ),
      'more' => await _pickMoreOptions(),
      _ => null,
    };
  }

  Future<JasprCreateOptions?> _pickMoreOptions() async {
    const items = [
      QuickPickItem(
        label: 'Static Mode, Multi Page',
        payload: 'static:auto|multi-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Static Mode, Single Page',
        payload: 'static:auto|single-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Static Mode, Embedded Flutter',
        payload: 'static:auto|multi-page|embedded|',
      ),
      QuickPickItem(
        label: 'Static Mode, No Routing',
        payload: 'static:auto|none|plugins-only|',
      ),
      QuickPickItem(
        label: 'Static Mode, Manual Hydration',
        payload: 'static|single-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Server Mode, Multi Page',
        payload: 'server:auto|multi-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Server Mode, Single Page',
        payload: 'server:auto|single-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Server Mode, Embedded Flutter',
        payload: 'server:auto|multi-page|embedded|',
      ),
      QuickPickItem(
        label: 'Server Mode, No Routing',
        payload: 'server:auto|none|plugins-only|',
      ),
      QuickPickItem(
        label: 'Server Mode, Manual Hydration',
        payload: 'server|single-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Client Mode, Single Page',
        payload: 'client|single-page|plugins-only|',
      ),
      QuickPickItem(
        label: 'Client Mode, Embedded Flutter',
        payload: 'client|single-page|embedded|',
      ),
      QuickPickItem(
        label: 'Client Mode, No Routing',
        payload: 'client|none||',
      ),
    ];

    final selected = await context.window.showQuickPick(
      items,
      placeholder: 'Select a configuration',
    );
    if (selected?.payload == null) return null;

    final parts = selected!.payload.toString().split('|');
    return JasprCreateOptions(
      mode: parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : null,
      routing: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      flutter: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
      backend: parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null,
    );
  }

  Future<String?> _promptProjectName(String parent) async {
    while (true) {
      final name = await context.window.showInputBox(
        prompt: 'Enter a name for your new project',
        value: 'my_jaspr_site',
      );
      if (name == null) return null;
      final trimmed = name.trim();
      final error = _validateProjectName(trimmed, parent);
      if (error == null) return trimmed;
      await context.window.showMessage(error, type: MessageType.warning);
    }
  }

  String? _validateProjectName(String input, String folderDir) {
    if (!RegExp(packageNameRegexSource).hasMatch(input)) {
      return 'Jaspr project names should be all lowercase, with underscores to separate words';
    }
    const banned = ['jaspr', 'jaspr_text', 'this'];
    if (banned.contains(input)) {
      return 'You may not use "$input" as the name for a Jaspr project';
    }
    if (Directory(path.join(folderDir, input)).existsSync()) {
      return 'A project with this name already exists within the selected directory';
    }
    return null;
  }

  Future<void> _runAndShow(
    List<String> args,
    String workingDirectory, {
    bool alwaysShow = false,
  }) async {
    final channel = await _channel();
    if (alwaysShow) await channel.show();
    await channel.append('> jaspr ${args.join(' ')}\n');

    final cmd = await sdkManager.getJasprCommand();
    final result = await context.shell.run(
      cmd.first,
      [...cmd.sublist(1), ...args],
      workingDirectory: workingDirectory,
    );

    await channel.append(result.stdout.toString());
    if (result.stderr.toString().trim().isNotEmpty) {
      await channel.append(result.stderr.toString());
    }
    await channel.show();

    if (result.exitCode != 0) {
      await context.window.showMessage(
        'jaspr ${args.first} exited with code ${result.exitCode}',
        type: MessageType.warning,
      );
    }
  }
}
