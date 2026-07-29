# lumide_jaspr

The Jaspr extension for [Lumide](https://lumide.dev/) IDE.

`lumide_jaspr` ports the core of the [Jaspr VS Code extension](https://marketplace.visualstudio.com/items?itemName=schultek.jaspr-code) to Lumide: project management, `jaspr daemon` serve/stop, and dual Server + Client debug attach.

## Features

- **Project detection** — activates for workspaces with `pubspec.yaml`; recognizes Jaspr via `dependencies.jaspr` or a top-level `jaspr:` key
- **CLI tools** — Doctor, Clean, New Project (curated templates)
- **Serve & Debug** — starts `jaspr daemon`, streams logs to the **Jaspr** output channel
- **Dual debug attach** — on Debug, attaches Lumide debug sessions for Server (`server.started`) and Client (`client.debugPort`)
- **Launch configs** — Run/Debug provider with schema; imports VS Code `type: jaspr` configs
- **Status bar** — running/stopped state and Stop Jaspr control

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

Or publish/install once available on pub.dev.

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

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `jaspr.logEntryLimit` | `5000` | Max lines in the Jaspr output channel |

## Launch schema

Configurations support:

- `cwd` — working directory
- `args` — forwarded to `jaspr daemon` (e.g. `["--release"]`)
- `env` — environment variables

## License

MIT
