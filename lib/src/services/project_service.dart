import 'dart:io';

import 'package:lumide_api/lumide_api.dart';
import 'package:path/path.dart' as path;

extension UriExtension on Uri {
  String toRealPath() {
    if (Platform.isWindows) {
      final buffer = StringBuffer();
      if (authority.isNotEmpty) {
        buffer.write('\\\\$authority');
      }

      if (pathSegments.isEmpty && authority.isEmpty) {
        return '\\';
      }

      for (var i = 0; i < pathSegments.length; i++) {
        final segment = pathSegments[i];

        final isDriveLetter = i == 0 &&
            segment.length == 2 &&
            segment[1] == ':' &&
            authority.isEmpty;

        if (!isDriveLetter) {
          buffer.write('\\');
        }
        buffer.write(segment);
      }

      final p = buffer.toString();

      if (p.startsWith('\\') && !p.contains(':')) {
        try {
          return File(p).absolute.path;
        } catch (_) {
          return p;
        }
      }

      return p;
    }
    return toFilePath();
  }
}

class ProjectService {
  final LumideContext context;

  final List<String> _cachedProjects = [];
  bool _projectsLoaded = false;

  ProjectService(this.context);

  Future<String> getWorkspaceRoot() async {
    final workspaceRootUri = await context.workspace.getRootUri();
    if (workspaceRootUri == null || workspaceRootUri.isEmpty) {
      throw Exception(
        'Open a workspace folder before creating a Jaspr project.',
      );
    }
    return workspaceRootUri;
  }

  void clearCaches() {
    _cachedProjects.clear();
    _projectsLoaded = false;
  }

  /// Returns a project root containing pubspec.yaml.
  Future<String> getProjectRoot([String? uri]) async {
    final hintedPath = _pathFromUriOrPath(uri);
    if (hintedPath != null) {
      final hintedRoot = await findProjectRootForPath(hintedPath);
      if (hintedRoot != null) return hintedRoot;
    }

    final workspaceRootUri = await context.workspace.getRootUri();
    if (workspaceRootUri != null) {
      if (await context.fs.exists(path.join(workspaceRootUri, 'pubspec.yaml'))) {
        return workspaceRootUri;
      }
    }

    throw Exception(
      'Workspace root containing a pubspec.yaml is required to use the Jaspr plugin.',
    );
  }

  Future<String?> findProjectRootForPath(String fileOrFolderPath) async {
    var current = fileOrFolderPath;
    final extension = path.extension(current);
    if (extension.isNotEmpty) {
      current = path.dirname(current);
    }

    final workspaceRoot = await context.workspace.getRootUri();
    final normalizedWorkspaceRoot =
        workspaceRoot == null ? null : path.normalize(workspaceRoot);

    while (true) {
      final pubspecPath = path.join(current, 'pubspec.yaml');
      if (await context.fs.exists(pubspecPath)) return current;

      final parent = path.dirname(current);
      if (parent == current) return null;
      if (normalizedWorkspaceRoot != null &&
          path.normalize(current) == normalizedWorkspaceRoot) {
        return null;
      }
      current = parent;
    }
  }

  String? _pathFromUriOrPath(String? uriOrPath) {
    if (uriOrPath == null || uriOrPath.isEmpty) return null;
    final parsed = Uri.tryParse(uriOrPath);
    if (parsed != null && parsed.isScheme('file')) {
      return parsed.toRealPath();
    }
    return uriOrPath;
  }

  String? pathFromMenuContext(Map<String, dynamic>? args) {
    final contextMap = _mapValue(args, 'context');
    if (contextMap == null) return null;

    final directFile = _mapValue(contextMap, 'file');
    if (_pathValue(directFile) case final filePath?) return filePath;

    final tab = _mapValue(contextMap, 'tab');
    final tabFile = _mapValue(tab, 'file');
    if (_pathValue(tabFile) case final tabPath?) return tabPath;

    final primary = _mapValue(contextMap, 'primary');
    if (_pathValue(primary) case final primaryPath?) return primaryPath;

    if (contextMap['selectedPaths'] case final List paths when paths.isNotEmpty) {
      final first = paths.first;
      if (first is String && first.isNotEmpty) return first;
    }

    final root = _mapValue(contextMap, 'root');
    return _pathValue(root);
  }

  String? folderFromMenuContext(Map<String, dynamic>? args) {
    final contextMap = _mapValue(args, 'context');
    if (contextMap == null) return null;

    final primary = _mapValue(contextMap, 'primary');
    final primaryPath = _pathValue(primary);
    if (primaryPath != null) {
      final type = primary?['type'];
      if (type == 'directory') return primaryPath;
      if (type == 'file') return path.dirname(primaryPath);
    }

    final contextPath = pathFromMenuContext(args);
    if (contextPath == null) return null;
    if (path.extension(contextPath).isNotEmpty) {
      return path.dirname(contextPath);
    }
    return contextPath;
  }

  Future<String?> projectRootFromMenuContext(
    Map<String, dynamic>? args,
  ) async {
    final contextPath = pathFromMenuContext(args);
    if (contextPath == null) return null;
    return findProjectRootForPath(contextPath);
  }

  Map<String, dynamic>? _mapValue(Map<dynamic, dynamic>? source, String key) {
    if (source == null) return null;
    final value = source[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String? _pathValue(Map<String, dynamic>? map) {
    if (map == null) return null;
    if (map['path'] case final String p when p.isNotEmpty) {
      return p;
    }
    if (map['uri'] case final String uri when uri.isNotEmpty) {
      return _pathFromUriOrPath(uri);
    }
    return null;
  }

  Future<List<String>> findAllProjects({bool forceRefresh = false}) async {
    if (_projectsLoaded && !forceRefresh) return _cachedProjects;

    final pubspecUris = await context.workspace.findFiles('**/pubspec.yaml');
    if (pubspecUris.isEmpty) {
      _cachedProjects.clear();
      _projectsLoaded = true;
      return [];
    }

    final projects = pubspecUris
        .map((uri) {
          final parsed = Uri.parse(uri);
          final filePath = parsed.toRealPath();
          return path.dirname(filePath);
        })
        .toSet()
        .toList();

    _cachedProjects
      ..clear()
      ..addAll(projects);
    _projectsLoaded = true;
    return _cachedProjects;
  }

  /// Whether [projectRoot] is a Jaspr project (has jaspr dependency or jaspr: key).
  Future<bool> isJasprProject(String projectRoot) async {
    final pubspecPath = path.join(projectRoot, 'pubspec.yaml');
    if (!await context.fs.exists(pubspecPath)) return false;

    try {
      final content = await context.fs.readString(pubspecPath);
      return pubspecReferencesJaspr(content);
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> findAllJasprProjects({bool forceRefresh = false}) async {
    final projects = await findAllProjects(forceRefresh: forceRefresh);
    final jasprProjects = <String>[];
    for (final project in projects) {
      if (await isJasprProject(project)) {
        jasprProjects.add(project);
      }
    }
    return jasprProjects;
  }
}

/// Pure helper for tests and callers that already have pubspec text.
bool pubspecReferencesJaspr(String content) {
  // Match top-level `jaspr:` or dependency entry for jaspr.
  final hasTopLevel = RegExp(
    r'^jaspr\s*:',
    multiLine: true,
  ).hasMatch(content);
  if (hasTopLevel) return true;

  final hasDependency = RegExp(
    r'^\s+jaspr\s*:',
    multiLine: true,
  ).hasMatch(content);
  return hasDependency;
}
