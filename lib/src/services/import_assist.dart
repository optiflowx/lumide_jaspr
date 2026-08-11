import 'package:lumide_import_assist/lumide_import_assist.dart' as assist;

export 'package:lumide_import_assist/lumide_import_assist.dart'
    show ImportSyncResult, insertImports, removeImports;

const String importJaspr = 'package:jaspr/jaspr.dart';
const String importJasprDom = 'package:jaspr/dom.dart';
const String importJasprClient = 'package:jaspr/client.dart';
const String importJasprServer = 'package:jaspr/server.dart';
const String importJasprRouter = 'package:jaspr_router/jaspr_router.dart';
const String importJasprFlutterEmbed =
    'package:jaspr_flutter_embed/jaspr_flutter_embed.dart';
const String importJasprTest = 'package:jaspr_test/jaspr_test.dart';

const List<String> managedImportUris = [
  importJaspr,
  importJasprDom,
  importJasprClient,
  importJasprServer,
  importJasprRouter,
  importJasprFlutterEmbed,
  importJasprTest,
];

final Set<String> managedImportUriSet = Set<String>.unmodifiable(
  managedImportUris,
);

/// Jaspr-specific import detection pack for [assist].
class JasprImportPack implements assist.ImportPack {
  const JasprImportPack();

  @override
  String get id => 'jaspr';

  @override
  assist.ImportSyntax get syntax => assist.dartImportSyntax;

  @override
  Set<String> get managedUris => managedImportUriSet;

  @override
  Set<String> detectNeeded(String source, {String? path}) =>
      detectImportUris(source, path: path);
}

const jasprImportPack = JasprImportPack();

/// Detects which Jaspr-related import URIs [source] likely needs.
Set<String> detectImportUris(String source, {String? path}) {
  final needed = <String>{};
  final fileName =
      path == null ? '' : path.replaceAll('\\', '/').split('/').last;
  final isTestFile = fileName.endsWith('_test.dart');

  if (_hasAny(source, _jasprCoreMarkers)) {
    needed.add(importJaspr);
  }
  if (_hasAny(source, _jasprDomMarkers)) {
    needed.add(importJasprDom);
  }
  if (_hasAny(source, _jasprClientMarkers)) {
    needed.add(importJasprClient);
  }
  if (_hasAny(source, _jasprServerMarkers)) {
    needed.add(importJasprServer);
  }
  if (_hasAny(source, _jasprRouterMarkers)) {
    needed.add(importJasprRouter);
  }
  if (_hasAny(source, _jasprFlutterEmbedMarkers)) {
    needed.add(importJasprFlutterEmbed);
  }
  if (isTestFile && _hasAny(source, _jasprTestMarkers)) {
    needed.add(importJasprTest);
  }

  return needed;
}

/// Returns package URIs needed by [source] but not yet imported/exported.
Set<String> neededImports(String source, {String? path}) =>
    assist.neededImports(source, jasprImportPack, path: path);

/// Managed import URIs present as `import` directives but not needed by usage.
Set<String> unusedImports(String source, {String? path}) =>
    assist.unusedImports(source, jasprImportPack, path: path);

/// Removes unused managed imports, then adds any still missing.
assist.ImportSyncResult syncImports(
  String source, {
  String? path,
  bool removeUnused = true,
}) =>
    assist.syncImports(
      source,
      jasprImportPack,
      path: path,
      removeUnused: removeUnused,
    );

bool _hasAny(String source, List<RegExp> patterns) {
  for (final pattern in patterns) {
    if (pattern.hasMatch(source)) return true;
  }
  return false;
}

final _jasprCoreMarkers = <RegExp>[
  RegExp(r'\bStatelessComponent\b'),
  RegExp(r'\bStatefulComponent\b'),
  RegExp(r'\bAsyncStatelessComponent\b'),
  RegExp(r'\bInheritedComponent\b'),
  RegExp(r'\bBuildContext\b'),
  RegExp(r'\bComponent\.'),
  RegExp(r'\.fragment\s*\('),
  RegExp(r'\.text\s*\('),
  RegExp(r'\.empty\s*\('),
  RegExp(r'\bState\s*<'),
  RegExp(r'\bKey\b'),
];

final _jasprDomMarkers = <RegExp>[
  RegExp(r'\bdiv\s*\('),
  RegExp(r'\bp\s*\('),
  RegExp(r'\ba\s*\('),
  RegExp(r'\bspan\s*\('),
  RegExp(r'\bbutton\s*\('),
  RegExp(r'\bh[1-6]\s*\('),
  RegExp(r'\bimg\s*\('),
  RegExp(r'\bul\s*\('),
  RegExp(r'\bli\s*\('),
  RegExp(r'\bform\s*\('),
  RegExp(r'\binput\s*\('),
  RegExp(r'\bevents\s*\('),
  RegExp(r'\bStyles\s*\('),
  RegExp(r'@css\b'),
  RegExp(r'\bcss\s*\('),
  RegExp(r'\btext\s*\('),
];

final _jasprClientMarkers = <RegExp>[
  RegExp(r'@client\b'),
  RegExp(r'\brunApp\s*\('),
  RegExp(r'\bClientApp\b'),
];

final _jasprServerMarkers = <RegExp>[
  RegExp(r'\bDocument\s*\('),
  RegExp(r'\bserveApp\s*\('),
  RegExp(r'\bServerApp\b'),
];

final _jasprRouterMarkers = <RegExp>[
  RegExp(r'\bRoute\s*\('),
  RegExp(r'\bRouter\s*\('),
  RegExp(r'\bLink\s*\('),
  RegExp(r'\bRouterState\b'),
];

final _jasprFlutterEmbedMarkers = <RegExp>[
  RegExp(r'\bFlutterEmbedView\b'),
  RegExp(r'\bFlutterApp\b'),
];

final _jasprTestMarkers = <RegExp>[
  RegExp(r'\btestComponents\s*\('),
  RegExp(r'\bpumpComponent\s*\('),
  RegExp(r'\bfindsOneComponent\b'),
];
