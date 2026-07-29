import 'dart:io';

import 'package:lumide_api/lumide_api.dart';

class SdkManager {
  final LumideContext context;

  SdkManager(this.context);

  List<String>? _resolvedJasprCommand;
  List<String>? _resolvedDartCommand;

  /// Resolves the `jaspr` CLI to an absolute command list.
  Future<List<String>> getJasprCommand() async {
    if (_resolvedJasprCommand != null) {
      return _resolvedJasprCommand!;
    }

    final resolved = await _resolveViaShell('jaspr');
    if (resolved != null) {
      _resolvedJasprCommand = [resolved];
      return _resolvedJasprCommand!;
    }

    _resolvedJasprCommand = ['jaspr'];
    return _resolvedJasprCommand!;
  }

  Future<List<String>> getDartCommand() async {
    if (_resolvedDartCommand != null) {
      return _resolvedDartCommand!;
    }

    final resolved = await _resolveViaShell('dart');
    if (resolved != null) {
      _resolvedDartCommand = [resolved];
      return _resolvedDartCommand!;
    }

    _resolvedDartCommand = ['dart'];
    return _resolvedDartCommand!;
  }

  Future<String?> _resolveViaShell(String command) async {
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final result = await context.shell.run(whichCmd, [command]);
      if (result.exitCode == 0) {
        final lines = result.stdout
            .toString()
            .trim()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();

        if (lines.isEmpty) return null;

        if (Platform.isWindows) {
          const winExts = ['.exe', '.bat', '.cmd'];
          for (final line in lines) {
            final lower = line.toLowerCase();
            if (winExts.any((ext) => lower.endsWith(ext))) {
              return line;
            }
          }
          return null;
        }

        return lines.first;
      }
    } catch (_) {}
    return null;
  }

  void clearCache() {
    _resolvedJasprCommand = null;
    _resolvedDartCommand = null;
  }

  /// Returns the installed jaspr CLI version string, or null if missing.
  Future<String?> getJasprVersion() async {
    try {
      final command = await getJasprCommand();
      final result = await context.shell.run(
        command.first,
        [...command.sublist(1), '--version'],
      );
      if (result.exitCode != 0) return null;
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return null;
      // Typical: "jaspr_cli version: 0.21.0" or bare "0.21.0"
      final match = RegExp(r'(\d+\.\d+\.\d+(?:[-+][\w.]+)?)').firstMatch(output);
      return match?.group(1) ?? output.split(RegExp(r'\s+')).last;
    } catch (_) {
      return null;
    }
  }
}

/// Compares dotted semantic versions; returns negative if [a] < [b].
int compareSemver(String a, String b) {
  List<int> parts(String v) {
    final core = v.split(RegExp(r'[-+]')).first;
    return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }

  final ap = parts(a);
  final bp = parts(b);
  final len = ap.length > bp.length ? ap.length : bp.length;
  for (var i = 0; i < len; i++) {
    final av = i < ap.length ? ap[i] : 0;
    final bv = i < bp.length ? bp[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}
