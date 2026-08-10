// commands
const String cmdJasprDoctor = 'jaspr.doctor';
const String cmdJasprClean = 'jaspr.clean';
const String cmdJasprCreate = 'jaspr.create';
const String cmdJasprServe = 'jaspr.serve';
const String cmdJasprStop = 'jaspr.stop';
const String cmdJasprDebug = 'jaspr.debug';
const String cmdJasprTools = 'jaspr.tools';
const String cmdJasprCleanForContext = 'jaspr.context.clean';
const String cmdJasprDoctorForContext = 'jaspr.context.doctor';
const String cmdJasprCreateForContext = 'jaspr.context.create';
const String cmdJasprEnsureImports = 'jaspr.ensureImports';

const String launchProviderJaspr = 'jaspr';
const String launchConfigCurrent = 'current';

// configuration
const String confLogEntryLimit = 'jaspr.logEntryLimit';
const int defaultLogEntryLimit = 5000;
const String confAutoImportOnSave = 'jaspr.autoImportOnSave';
const bool defaultAutoImportOnSave = true;
const String confRemoveUnusedImportsOnSave = 'jaspr.removeUnusedImportsOnSave';
const bool defaultRemoveUnusedImportsOnSave = true;

// output
const String channelJaspr = 'Jaspr';

// icons
const String iconZap = 'zap';
const String iconPlay = 'play';
const String iconBug = 'bug';
const String iconStop = 'stop';
const String iconGlobe = 'globe';
const String iconTerminal = 'terminal';

// CLI
const String minimumJasprVersion = '0.23.0';
const String packageNameRegexSource = r'^[a-z][a-z0-9_]*$';
