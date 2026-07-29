import 'package:lumide_api/lumide_api.dart';
import 'package:lumide_jaspr/src/constants.dart';

class StatusBarService {
  final LumideContext context;

  static const String _statusItemId = 'jaspr.status';
  static const String _stopItemId = 'jaspr.stop';

  StatusBarService(this.context);

  Future<void> init() async {
    await context.statusBar.createItem(
      id: _statusItemId,
      text: 'Jaspr',
      alignment: 'left',
      priority: 20,
      tooltip: 'Jaspr Tools',
      command: cmdJasprTools,
    );
  }

  Future<void> updateVersion(String version) async {
    await context.statusBar.updateItem(
      _statusItemId,
      text: 'Jaspr $version',
      tooltip: 'Jaspr CLI $version',
      command: cmdJasprTools,
    );
  }

  Future<void> setStarting() async {
    await context.statusBar.updateItem(
      _statusItemId,
      text: 'Starting Jaspr...',
      tooltip: 'Starting Jaspr daemon',
      command: cmdJasprTools,
    );
    await _ensureStopItem();
  }

  Future<void> setRunning() async {
    await context.statusBar.updateItem(
      _statusItemId,
      text: 'Jaspr is running',
      tooltip: 'Jaspr daemon is running',
      command: cmdJasprTools,
    );
    await _ensureStopItem();
  }

  Future<void> setFailed() async {
    await context.statusBar.updateItem(
      _statusItemId,
      text: 'Jaspr failed',
      tooltip: 'Jaspr failed to start',
      command: cmdJasprTools,
    );
    await _hideStopItem();
  }

  Future<void> setStopped() async {
    await context.statusBar.updateItem(
      _statusItemId,
      text: 'Jaspr',
      tooltip: 'Jaspr Tools',
      command: cmdJasprTools,
    );
    await _hideStopItem();
  }

  Future<void> _ensureStopItem() async {
    try {
      await context.statusBar.createItem(
        id: _stopItemId,
        text: 'Stop Jaspr',
        alignment: 'left',
        priority: 19,
        tooltip: 'Stop Jaspr',
        command: cmdJasprStop,
      );
    } catch (_) {
      await context.statusBar.updateItem(
        _stopItemId,
        text: 'Stop Jaspr',
        tooltip: 'Stop Jaspr',
        command: cmdJasprStop,
      );
      await context.statusBar.show(_stopItemId);
    }
  }

  Future<void> _hideStopItem() async {
    try {
      await context.statusBar.hide(_stopItemId);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await context.statusBar.disposeItem(_statusItemId);
    try {
      await context.statusBar.disposeItem(_stopItemId);
    } catch (_) {}
  }
}
