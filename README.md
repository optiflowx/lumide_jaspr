# lumide_jaspr

Jaspr web framework support for [Lumide](https://lumide.dev/) IDE.

Project management, `jaspr daemon` serve/stop, and dual Server + Client debug attach for Jaspr apps.

## Features

- **Project detection** — activates for workspaces with `pubspec.yaml`; recognizes Jaspr via `dependencies.jaspr` or a top-level `jaspr:` key
- **CLI tools** — Doctor, Clean, New Project (curated templates)
- **Serve & Debug** — starts `jaspr daemon`, streams logs to the **Jaspr** output channel
- **Dual debug attach** — on Debug, attaches Lumide debug sessions for Server (`server.started`) and Client (`client.debugPort`)
- **Launch configs** — Run/Debug provider with schema; imports existing `type: jaspr` launch configurations
- **Status bar** — running/stopped state and Stop Jaspr control
- **Dart snippets** — Jaspr component/HTML/event prefixes in `.dart` files
- **Import assist** — on save (or via command), add missing and remove unused managed `jaspr` / `dom` / `client` / `server` / `jaspr_router` imports (via shared `lumide_import_assist`)

## Requirements

- [Lumide](https://lumide.dev/) IDE
- Dart SDK on `PATH`
- Jaspr CLI (`jaspr`) on `PATH` — install with:

```bash
dart pub global activate jaspr_cli
```

Minimum CLI version: **0.23.0**

## Load in Lumide

1. Open Lumide → **Plugins** pane
2. **Load Local Plugin**
3. Select this package directory (`packages/lumide_jaspr`)

Or install from pub.dev when published.

Recommended companion: load [`lumide_dart`](../lumide_dart) for language-level snippets (`dprint`, `ftest`, …) and pubspec file nesting. Plugins cannot depend on each other at runtime — install both if you want both surfaces.

## Commands

| Command | Description |
| --- | --- |
| Jaspr: New Project | Scaffold a project from curated templates |
| Jaspr: Serve | Start `jaspr daemon` (run, no debugger) |
| Jaspr: Debug | Start daemon and attach Server/Client debuggers |
| Jaspr: Stop | Shut down the daemon and debug sessions |
| Jaspr: Doctor | Run `jaspr doctor` |
| Jaspr: Clean | Run `jaspr clean` |
| Jaspr: Tools Menu | Quick pick of common actions |
| Jaspr: Ensure Imports | Sync managed Jaspr imports for the active file (add + remove unused) |

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `jaspr.logEntryLimit` | `5000` | Max lines in the Jaspr output channel |
| `jaspr.autoImportOnSave` | `true` | Sync Jaspr imports when saving `.dart` files |
| `jaspr.removeUnusedImportsOnSave` | `true` | With auto-import on save, also drop unused managed Jaspr imports |

## Imports

### Snippet / save assist (this plugin)

Text snippets do not go through Dart completion, so they do not trigger LSP auto-import. After inserting a snippet (or when symbols change), **save** the file or run **Jaspr: Ensure Imports**.

Heuristics may **add** or **remove** these managed imports (not a full Organize Imports for every package):

| Import | Typical triggers |
| --- | --- |
| `package:jaspr/jaspr.dart` | `StatelessComponent`, `BuildContext`, `Component.*`, … |
| `package:jaspr/dom.dart` | `div(`, `a(`, `text(`, `events(`, `@css`, … |
| `package:jaspr/client.dart` | `@client`, `runApp(`, … |
| `package:jaspr/server.dart` | `Document(`, `serveApp(`, … |
| `package:jaspr_router/jaspr_router.dart` | `Route(`, `Router(`, `Link(`, … |
| `package:jaspr_flutter_embed/...` | Flutter embed markers |
| `package:jaspr_test/...` | `testComponents` in `*_test.dart` |

Rare APIs outside the heuristic table may keep an “unused” import or, less often, drop one still needed — turn off `jaspr.removeUnusedImportsOnSave` if that happens.

### Dart LSP auto-import (Lumide host)

General Dart auto-import (like Dart-Code’s `dart.autoImportCompletions`) comes from Lumide’s **analysis_server** when completion / quick fix can apply `workspace/applyEdit`. Prefer completing a symbol from the suggestion list if you want the host to insert the import. Full unused-import cleanup for non-Jaspr packages also belongs to the Dart language tools / Organize Imports when available.

## Snippets

Type a prefix in a `.dart` file and accept the completion:

| Prefix | Inserts |
| --- | --- |
| `jstless` | `StatelessComponent` |
| `jstful` | `StatefulComponent` |
| `jhtml` | HTML component call |
| `jtext` | `text("...")` |
| `jstyls` | `@css` styles list |
| `jevt` | Event handler map |
| `jclick` | `onClick` event handler |
| `jinherited` | `InheritedComponent` + `of(context)` |
| `jasync` | `AsyncStatelessComponent` |
| `jclient` | `@client` `StatelessComponent` |
| `jfragment` | `.fragment([...])` |
| `jroute` | `jaspr_router` `Route` |
| `ja` | Anchor / link |

## Launch schema

Configurations support:

- `cwd` — working directory
- `args` — forwarded to `jaspr daemon` (e.g. `["--release"]`)
- `env` — environment variables

## Credits

Built for Lumide using the [Jaspr](https://github.com/schultek/jaspr) framework and CLI. Serve/debug workflow and core snippet prefixes adapted from the Jaspr editor tooling by [schultek](https://github.com/schultek). See [NOTICE](NOTICE) for details.

## License

MIT. See [LICENSE](LICENSE).
