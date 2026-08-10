import 'package:lumide_jaspr/src/services/import_assist.dart';
import 'package:test/test.dart';

void main() {
  group('detectImportUris', () {
    test('detects jaspr core from StatelessComponent', () {
      const source = '''
class Home extends StatelessComponent {
  Component build(BuildContext context) => Component.empty();
}
''';
      expect(detectImportUris(source), contains(importJaspr));
    });

    test('detects jaspr/dom from div and text', () {
      const source = '''
final c = div([text('hi')]);
''';
      expect(detectImportUris(source), contains(importJasprDom));
    });

    test('detects client from @client', () {
      const source = '''
@client
class Counter extends StatelessComponent {}
''';
      final uris = detectImportUris(source);
      expect(uris, contains(importJasprClient));
      expect(uris, contains(importJaspr));
    });

    test('detects server from Document', () {
      const source = '''
Component build() => Document(title: 'Hi', body: div([]));
''';
      final uris = detectImportUris(source);
      expect(uris, contains(importJasprServer));
      expect(uris, contains(importJasprDom));
    });

    test('detects router from Route', () {
      const source = '''
final routes = [Route(path: '/', builder: (c, s) => Home())];
''';
      expect(detectImportUris(source), contains(importJasprRouter));
    });

    test('detects jaspr_test only for test files', () {
      const source = '''
void main() {
  testComponents('x', (tester) async {});
}
''';
      expect(detectImportUris(source), isNot(contains(importJasprTest)));
      expect(
        detectImportUris(source, path: 'test/home_test.dart'),
        contains(importJasprTest),
      );
    });
  });

  group('neededImports', () {
    test('skips already imported uris', () {
      const source = '''
import 'package:jaspr/jaspr.dart';

class Home extends StatelessComponent {}
''';
      expect(neededImports(source), isEmpty);
    });

    test('returns only missing uris', () {
      const source = '''
import 'package:jaspr/jaspr.dart';

class Home extends StatelessComponent {
  Component build(BuildContext context) => div([]);
}
''';
      expect(neededImports(source), {importJasprDom});
    });
  });

  group('insertImports', () {
    test('inserts after existing imports', () {
      const source = '''
import 'dart:async';

class A {}
''';
      final result = insertImports(source, {importJaspr});
      expect(
        result,
        '''
import 'dart:async';
import 'package:jaspr/jaspr.dart';

class A {}
''',
      );
    });

    test('inserts at top when no directives', () {
      const source = 'class A {}\n';
      final result = insertImports(source, {importJasprDom});
      expect(result.startsWith("import 'package:jaspr/dom.dart';\n\n"), isTrue);
      expect(result.contains('class A {}'), isTrue);
    });

    test('is idempotent when uris empty', () {
      const source = 'class A {}';
      expect(insertImports(source, {}), source);
    });

    test('sorts multiple imports alphabetically by URI', () {
      const source = 'class A {}\n';
      final result = insertImports(source, {
        importJasprRouter,
        importJaspr,
        importJasprDom,
      });
      // package:jaspr/dom.dart < package:jaspr/jaspr.dart < package:jaspr_router/...
      final dom = result.indexOf("import '$importJasprDom';");
      final jaspr = result.indexOf("import '$importJaspr';");
      final router = result.indexOf("import '$importJasprRouter';");
      expect(dom, lessThan(jaspr));
      expect(jaspr, lessThan(router));
    });
  });

  group('unusedImports / removeImports', () {
    test('detects unused managed dom import', () {
      const source = '''
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

class Home extends StatelessComponent {}
''';
      expect(unusedImports(source), {importJasprDom});
    });

    test('keeps dom when div is used', () {
      const source = '''
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

class Home extends StatelessComponent {
  Component build(BuildContext context) => div([]);
}
''';
      expect(unusedImports(source), isEmpty);
    });

    test('does not treat unrelated packages as unused managed', () {
      const source = '''
import 'package:http/http.dart';
import 'package:jaspr/dom.dart';

class A {}
''';
      expect(unusedImports(source), {importJasprDom});
      final removed = removeImports(source, unusedImports(source));
      expect(removed, contains("import 'package:http/http.dart';"));
      expect(removed, isNot(contains("import 'package:jaspr/dom.dart';")));
    });

    test('does not remove export directives', () {
      const source = '''
export 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

class A {}
''';
      final removed = removeImports(source, {importJaspr, importJasprDom});
      expect(removed, contains("export 'package:jaspr/jaspr.dart';"));
      expect(removed, isNot(contains("import 'package:jaspr/dom.dart';")));
    });

    test('removes import with show/as clauses', () {
      const source = '''
import 'package:jaspr/dom.dart' as dom show div;

class A {}
''';
      final removed = removeImports(source, {importJasprDom});
      expect(removed.trim(), 'class A {}');
    });
  });

  group('syncImports', () {
    test('adds missing and removes unused in one pass', () {
      const source = '''
import 'package:jaspr/dom.dart';

class Home extends StatelessComponent {
  Component build(BuildContext context) => Component.empty();
}
''';
      final result = syncImports(source);
      expect(result.removed, {importJasprDom});
      expect(result.added, {importJaspr});
      expect(result.source, contains("import 'package:jaspr/jaspr.dart';"));
      expect(result.source, isNot(contains("import 'package:jaspr/dom.dart';")));
    });

    test('removeUnused false only adds', () {
      const source = '''
import 'package:jaspr/dom.dart';

class Home extends StatelessComponent {}
''';
      final result = syncImports(source, removeUnused: false);
      expect(result.removed, isEmpty);
      expect(result.added, {importJaspr});
      expect(result.source, contains("import 'package:jaspr/dom.dart';"));
    });
  });
}
