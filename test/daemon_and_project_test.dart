import 'package:lumide_jaspr/src/services/project_service.dart';
import 'package:lumide_jaspr/src/services/sdk_manager.dart';
import 'package:lumide_jaspr/src/services/serve_daemon_service.dart';
import 'package:test/test.dart';

void main() {
  group('parseDaemonLine', () {
    test('parses JSON array events', () {
      final event = parseDaemonLine(
        '[{"event":"server.started","params":{"vmServiceUri":"ws://127.0.0.1:8181"}}]',
      );
      expect(event, isNotNull);
      expect(event!.name, 'server.started');
      expect(event.params['vmServiceUri'], 'ws://127.0.0.1:8181');
    });

    test('parses client.debugPort events', () {
      final event = parseDaemonLine(
        '[{"event":"client.debugPort","params":{"wsUri":"ws://127.0.0.1:9","appId":"a1"}}]',
      );
      expect(event!.name, 'client.debugPort');
      expect(event.params['wsUri'], 'ws://127.0.0.1:9');
      expect(event.params['appId'], 'a1');
    });

    test('treats plain text as daemon.log', () {
      final event = parseDaemonLine('Serving at http://localhost:8080');
      expect(event!.name, 'daemon.log');
      expect(event.params['message'], 'Serving at http://localhost:8080');
    });

    test('ignores empty lines', () {
      expect(parseDaemonLine('   '), isNull);
    });
  });

  group('pubspecReferencesJaspr', () {
    test('detects dependencies.jaspr', () {
      const pubspec = '''
name: demo
dependencies:
  jaspr: ^0.21.0
''';
      expect(pubspecReferencesJaspr(pubspec), isTrue);
    });

    test('detects top-level jaspr key', () {
      const pubspec = '''
name: demo
jaspr:
  mode: static
dependencies:
  http: any
''';
      expect(pubspecReferencesJaspr(pubspec), isTrue);
    });

    test('rejects unrelated packages', () {
      const pubspec = '''
name: demo
dependencies:
  flutter:
    sdk: flutter
''';
      expect(pubspecReferencesJaspr(pubspec), isFalse);
    });
  });

  group('compareSemver', () {
    test('orders versions', () {
      expect(compareSemver('0.22.0', '0.23.0'), lessThan(0));
      expect(compareSemver('0.23.0', '0.23.0'), 0);
      expect(compareSemver('0.24.0', '0.23.0'), greaterThan(0));
    });
  });
}
