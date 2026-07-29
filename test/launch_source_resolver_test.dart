import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/src/constants.dart';
import 'package:lumide_jaspr/src/services/launch_source_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('importVscodeJasprLaunch', () {
    test('imports type jaspr configs', () async {
      final result = await importVscodeJasprLaunch(
        const LumideForeignLaunchConfiguration(
          format: 'vscode',
          name: 'My Site',
          raw: {
            'type': 'jaspr',
            'request': 'launch',
            'cwd': '.',
            'args': ['--release'],
          },
        ),
      );

      expect(result.fidelity, LumideLaunchImportFidelity.exact);
      expect(result.configuration?.providerId, launchProviderJaspr);
      expect(result.configuration?.config['args'], ['--release']);
    });

    test('rejects non-jaspr types', () async {
      final result = await importVscodeJasprLaunch(
        const LumideForeignLaunchConfiguration(
          format: 'vscode',
          name: 'Dart',
          raw: {'type': 'dart', 'request': 'launch'},
        ),
      );
      expect(result.fidelity, LumideLaunchImportFidelity.unsupported);
    });
  });

  group('resolveJasprLaunchSource', () {
    test('resolves cwd and args', () {
      final resolution = resolveJasprLaunchSource(
        const LumideLaunchSourceConfiguration(
          id: 'site',
          name: 'Site',
          providerId: launchProviderJaspr,
          kinds: [LumideLaunchKind.run, LumideLaunchKind.debug],
          config: {
            'cwd': r'${workspaceFolder}/apps/web',
            'args': ['--release'],
          },
        ),
        projectRoot: r'C:\work\demo',
      );

      expect(resolution.configuration, isNotNull);
      expect(resolution.configuration!.arguments['args'], ['--release']);
      expect(
        resolution.configuration!.arguments['cwd'],
        r'${workspaceFolder}/apps/web',
      );
    });
  });
}
