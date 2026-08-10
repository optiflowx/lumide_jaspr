// Pure helpers for detecting and inserting Jaspr-related imports.

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

/// Result of adding missing and/or removing unused managed imports.
class ImportSyncResult {
  const ImportSyncResult({
    required this.source,
    this.added = const {},
    this.removed = const {},
  });

  final String source;
  final Set<String> added;
  final Set<String> removed;

  bool get isNoOp => added.isEmpty && removed.isEmpty;
}

final _importOrExportOrPart = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

final _importDirectiveOnly = RegExp(
  r'''^\s*import\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Returns package URIs that appear to be needed by [source] but are not yet
/// imported/exported.
Set<String> neededImports(String source, {String? path}) {
  final existing = existingImportUris(source);
  final detected = detectImportUris(source, path: path);
  return detected.difference(existing);
}

/// Managed import URIs present as `import` directives but not needed by usage.
Set<String> unusedImports(String source, {String? path}) {
  final existing = existingImportDirectiveUris(source);
  final detected = detectImportUris(source, path: path);
  return existing.intersection(managedImportUriSet).difference(detected);
}

/// Removes unused managed imports, then adds any still missing.
ImportSyncResult syncImports(
  String source, {
  String? path,
  bool removeUnused = true,
}) {
  final detected = detectImportUris(source, path: path);
  final toRemove = removeUnused ? unusedImports(source, path: path) : <String>{};
  var next = removeImports(source, toRemove);
  final toAdd = detected.difference(existingImportUris(next));
  next = insertImports(next, toAdd);
  return ImportSyncResult(source: next, added: toAdd, removed: toRemove);
}

/// Detects which Jaspr-related import URIs [source] likely needs.
Set<String> detectImportUris(String source, {String? path}) {
  final needed = <String>{};
  final fileName = path == null ? '' : path.replaceAll('\\', '/').split('/').last;
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

Set<String> existingImportUris(String source) {
  final uris = <String>{};
  for (final match in _importOrExportOrPart.allMatches(source)) {
    final uri = match.group(1);
    if (uri != null && uri.isNotEmpty) {
      uris.add(uri);
    }
  }
  return uris;
}

/// URIs from `import` directives only (not `export` / `part`).
Set<String> existingImportDirectiveUris(String source) {
  final uris = <String>{};
  for (final match in _importDirectiveOnly.allMatches(source)) {
    final uri = match.group(1);
    if (uri != null && uri.isNotEmpty) {
      uris.add(uri);
    }
  }
  return uris;
}

/// Removes whole `import 'uri'…;` lines for [uris]. Does not touch exports.
String removeImports(String source, Set<String> uris) {
  if (uris.isEmpty) return source;

  final lines = source.split('\n');
  final kept = <String>[];
  for (final line in lines) {
    final uri = _importUriFromLine(line);
    if (uri != null && uris.contains(uri)) {
      continue;
    }
    kept.add(line);
  }

  // Collapse excessive blank lines left at the top of the file.
  final collapsed = <String>[];
  var leadingBlank = true;
  var previousBlank = false;
  for (final line in kept) {
    final isBlank = line.trim().isEmpty;
    if (leadingBlank && isBlank) continue;
    if (isBlank && previousBlank) continue;
    leadingBlank = false;
    previousBlank = isBlank;
    collapsed.add(line);
  }
  return collapsed.join('\n');
}

String? _importUriFromLine(String line) {
  final match = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"][^;]*;\s*$''',
  ).firstMatch(line);
  return match?.group(1);
}

/// Inserts missing `import '…';` lines after the last directive block.
/// Returns [source] unchanged when [uris] is empty.
String insertImports(String source, Set<String> uris) {
  if (uris.isEmpty) return source;

  final sorted = uris.toList()
    ..sort((a, b) => a.compareTo(b));
  final importBlock = sorted.map((uri) => "import '$uri';").join('\n');

  final lines = source.split('\n');
  var lastDirectiveIndex = -1;
  var sawLibrary = false;

  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;
    if (trimmed.startsWith('library ')) {
      sawLibrary = true;
      lastDirectiveIndex = i;
      continue;
    }
    if (trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed.startsWith('part ')) {
      lastDirectiveIndex = i;
      continue;
    }
    break;
  }

  if (lastDirectiveIndex >= 0) {
    lines.insert(lastDirectiveIndex + 1, importBlock);
    return lines.join('\n');
  }

  if (sawLibrary) {
    // Unreachable if library set lastDirectiveIndex, but keep safe.
    return '$importBlock\n\n$source';
  }

  if (source.isEmpty) return '$importBlock\n';
  return '$importBlock\n\n$source';
}

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
