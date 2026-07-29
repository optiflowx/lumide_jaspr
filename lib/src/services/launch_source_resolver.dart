import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/src/constants.dart';
import 'package:path/path.dart' as path;

LumideLaunchResolution resolveJasprLaunchSource(
  LumideLaunchSourceConfiguration source, {
  required String projectRoot,
}) {
  if (source.providerId != launchProviderJaspr) {
    return const LumideLaunchResolution();
  }

  final diagnostics = <LumideLaunchConfigurationDiagnostic>[];
  final config = source.config;
  final cwd = _string(config, 'cwd');
  final args = _stringList(config, 'args', diagnostics);
  final env = _stringMap(config, 'env', diagnostics);
  final kinds = source.kinds.isEmpty
      ? const [LumideLaunchKind.run, LumideLaunchKind.debug]
      : source.kinds;

  if (diagnostics.any(
    (d) => d.severity == LumideLaunchDiagnosticSeverity.error,
  )) {
    return LumideLaunchResolution(diagnostics: diagnostics);
  }

  final resolvedCwd = _resolveWorkspacePath(cwd, projectRoot) ?? projectRoot;

  return LumideLaunchResolution(
    configuration: LumideLaunchConfiguration(
      id: source.id,
      label: source.name,
      kinds: kinds,
      deduplicationKey: path.normalize(resolvedCwd),
      description: path.basename(resolvedCwd),
      icon: iconGlobe,
      arguments: {
        'canLaunch': true,
        'cwd': cwd ?? projectRoot,
        if (args.isNotEmpty) 'args': args,
        if (env.isNotEmpty) 'env': env,
        'targetLabel': source.name,
        'targetTooltip': resolvedCwd,
      },
    ),
    diagnostics: diagnostics,
  );
}

Future<LumideLaunchImportResult> importVscodeJasprLaunch(
  LumideForeignLaunchConfiguration source,
) async {
  final raw = source.raw;
  final type = raw['type']?.toString();
  if (source.format != 'vscode' || type != 'jaspr') {
    return const LumideLaunchImportResult(
      fidelity: LumideLaunchImportFidelity.unsupported,
    );
  }

  final diagnostics = <LumideLaunchConfigurationDiagnostic>[];
  if (_containsUnsupportedVariable(raw)) {
    return const LumideLaunchImportResult(
      fidelity: LumideLaunchImportFidelity.unsupported,
      diagnostics: [
        LumideLaunchConfigurationDiagnostic(
          severity: LumideLaunchDiagnosticSeverity.error,
          message:
              'Command and input variables require manual migration in Lumide.',
        ),
      ],
    );
  }

  const unsupportedFields = {'preLaunchTask', 'postDebugTask', 'envFile'};
  for (final field in unsupportedFields) {
    if (raw.containsKey(field)) {
      diagnostics.add(
        LumideLaunchConfigurationDiagnostic(
          severity: LumideLaunchDiagnosticSeverity.warning,
          message: 'VS Code field "$field" requires manual migration.',
          path: '\$.$field',
        ),
      );
    }
  }

  final config = <String, Object?>{
    if (raw['cwd'] case final String cwd) 'cwd': cwd,
    if (raw['args'] case final List args) 'args': args,
    if (raw['env'] case final Map env)
      'env': env.map((key, value) => MapEntry(key.toString(), value)),
  };

  final id = source.name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  return LumideLaunchImportResult(
    fidelity: diagnostics.isEmpty
        ? LumideLaunchImportFidelity.exact
        : LumideLaunchImportFidelity.partial,
    configuration: LumideLaunchSourceConfiguration(
      id: id,
      name: source.name,
      providerId: launchProviderJaspr,
      kinds: const [LumideLaunchKind.run, LumideLaunchKind.debug],
      config: config,
    ),
    diagnostics: diagnostics,
  );
}

String? _resolveWorkspacePath(String? value, String workspaceRoot) {
  if (value == null || value.isEmpty) return null;
  final expanded = value
      .replaceAll(r'${workspaceFolder}', workspaceRoot)
      .replaceAll(r'${workspaceRoot}', workspaceRoot);
  if (expanded.contains(r'${')) return expanded;
  if (path.isAbsolute(expanded)) return path.normalize(expanded);
  return path.normalize(path.join(workspaceRoot, expanded));
}

String? _string(Map<String, Object?> config, String key) {
  final value = config[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

List<String> _stringList(
  Map<String, Object?> config,
  String key,
  List<LumideLaunchConfigurationDiagnostic> diagnostics,
) {
  final value = config[key];
  if (value == null) return const [];
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  diagnostics.add(
    LumideLaunchConfigurationDiagnostic(
      severity: LumideLaunchDiagnosticSeverity.error,
      message: '$key must be an array of strings.',
      path: '\$.config.$key',
    ),
  );
  return const [];
}

Map<String, String> _stringMap(
  Map<String, Object?> config,
  String key,
  List<LumideLaunchConfigurationDiagnostic> diagnostics,
) {
  final value = config[key];
  if (value == null) return const {};
  if (value is Map && value.values.every((item) => item is String)) {
    return value.map(
      (mapKey, mapValue) => MapEntry(mapKey.toString(), mapValue as String),
    );
  }
  diagnostics.add(
    LumideLaunchConfigurationDiagnostic(
      severity: LumideLaunchDiagnosticSeverity.error,
      message: '$key must contain string values.',
      path: '\$.config.$key',
    ),
  );
  return const {};
}

bool _containsUnsupportedVariable(Object? value) {
  return switch (value) {
    final String text =>
      text.contains(r'${command:') || text.contains(r'${input:'),
    final List values => values.any(_containsUnsupportedVariable),
    final Map values => values.values.any(_containsUnsupportedVariable),
    _ => false,
  };
}
