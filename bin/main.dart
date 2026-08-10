import 'dart:async';

import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/lumide_jaspr.dart';
import 'package:lumide_jaspr/src/constants.dart';

void main() => JasprPlugin().run();

class JasprPlugin extends LumidePlugin {
  late LogService logService;
  late StatusBarService statusBarService;
  late ProjectService projectService;
  late SdkManager sdkManager;
  late JasprService jasprService;
  late ServeDaemonService daemonService;
  late DebugSessionService debugSessionService;
  late RunService runService;
  late ImportAssistService importAssistService;

  @override
  Future<void> onActivate(LumideContext context) async {
    logService = LogService(log);
    statusBarService = StatusBarService(context);
    projectService = ProjectService(context);
    sdkManager = SdkManager(context);
    jasprService = JasprService(
      context,
      projectService,
      sdkManager,
      statusBarService,
      logService,
    );
    daemonService = ServeDaemonService(
      sdkManager: sdkManager,
      logService: logService,
    );
    debugSessionService = DebugSessionService(context, logService);
    runService = RunService(
      context: context,
      projectService: projectService,
      jasprService: jasprService,
      daemonService: daemonService,
      debugSessionService: debugSessionService,
      statusBarService: statusBarService,
      logService: logService,
    );
    importAssistService = ImportAssistService(
      context,
      projectService,
      logService,
    );

    jasprService
      ..onServe = runService.serve
      ..onDebug = runService.debug
      ..onStop = runService.stop;

    await runService.init();
    await statusBarService.init();
    await importAssistService.init();

    unawaited(jasprService.checkSdk());

    await _registerCommands(context);
    await _registerMenuActions(context);

    await context.window.showMessage('Jaspr plugin ready');
  }

  Future<void> _registerCommands(LumideContext context) async {
    await Future.wait([
      context.commands.registerCommand(
        id: cmdJasprDoctor,
        title: 'Jaspr: Doctor',
        callback: ([args]) => jasprService.doctor(),
      ),
      context.commands.registerCommand(
        id: cmdJasprClean,
        title: 'Jaspr: Clean',
        callback: ([args]) => jasprService.clean(),
      ),
      context.commands.registerCommand(
        id: cmdJasprCreate,
        title: 'Jaspr: New Project',
        callback: ([args]) => jasprService.create(),
      ),
      context.commands.registerCommand(
        id: cmdJasprServe,
        title: 'Jaspr: Serve',
        callback: ([args]) => runService.serve(),
      ),
      context.commands.registerCommand(
        id: cmdJasprDebug,
        title: 'Jaspr: Debug',
        callback: ([args]) => runService.debug(),
      ),
      context.commands.registerCommand(
        id: cmdJasprStop,
        title: 'Jaspr: Stop',
        callback: ([args]) => runService.stop(),
      ),
      context.commands.registerCommand(
        id: cmdJasprTools,
        title: 'Jaspr: Tools Menu',
        callback: ([args]) => jasprService.showToolsMenu(args),
      ),
      context.commands.registerCommand(
        id: cmdJasprCleanForContext,
        title: 'Jaspr: Clean Here',
        callback: ([args]) => jasprService.cleanForContext(args),
      ),
      context.commands.registerCommand(
        id: cmdJasprDoctorForContext,
        title: 'Jaspr: Doctor Here',
        callback: ([args]) => jasprService.doctorForContext(args),
      ),
      context.commands.registerCommand(
        id: cmdJasprCreateForContext,
        title: 'Jaspr: New Project Here',
        callback: ([args]) => jasprService.createForContext(args),
      ),
      context.commands.registerCommand(
        id: cmdJasprEnsureImports,
        title: 'Jaspr: Ensure Imports',
        callback: ([args]) => importAssistService.ensureImportsForActiveDocument(),
      ),
    ]);
  }

  Future<void> _registerMenuActions(LumideContext context) async {
    await Future.wait([
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'create_file_tree',
          title: 'Create Jaspr Project Here',
          command: cmdJasprCreateForContext,
          location: LumideMenuLocation.fileTreeItem,
          group: 'create',
          priority: 130,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'clean_file_tree',
          title: 'Jaspr Clean',
          command: cmdJasprCleanForContext,
          location: LumideMenuLocation.fileTreeItem,
          group: 'tools',
          priority: 100,
        ),
      ),
      context.menus.registerAction(
        const LumideMenuAction(
          id: 'doctor_file_tree',
          title: 'Jaspr Doctor',
          command: cmdJasprDoctorForContext,
          location: LumideMenuLocation.fileTreeItem,
          group: 'tools',
          priority: 90,
        ),
      ),
    ]);
  }

  @override
  Future<void> onDeactivate() async {
    await importAssistService.dispose();
    await runService.dispose();
    await jasprService.dispose();
    await statusBarService.dispose();
  }
}
