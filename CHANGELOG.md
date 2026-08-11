## 0.1.6

- Use shared `lumide_import_assist` library for import sync (`JasprImportPack`)
- Move pubspec file nesting to companion `lumide_dart` plugin (install alongside for nesting + language snippets)

## 0.1.5

- Remove unused managed Jaspr imports on save / **Jaspr: Ensure Imports**
- Setting `jaspr.removeUnusedImportsOnSave` (default true)
- Sync pass: add missing + remove unused in one edit

## 0.1.4

- Add Jaspr import assist on save and **Jaspr: Ensure Imports**
- Heuristics for `jaspr`, `jaspr/dom`, `jaspr/client`, `jaspr/server`, `jaspr_router`, embed, and test imports
- Setting `jaspr.autoImportOnSave` (default true)
- Document Dart LSP vs snippet import behavior in README

## 0.1.3

- Add Dart snippet contributions via `lumide_api` 1.9.0 `contributes.snippets`
- Port jaspr-code prefixes (`jstless`, `jstful`, `jhtml`, `jtext`, `jstyls`, `jevt`, `jclick`)
- Add extra snippets: `jinherited`, `jasync`, `jclient`, `jfragment`, `jroute`, `ja`

## 0.1.2

- Align plugin metadata with `lumide_material_theme` (`publisher`, description wording)
- README and NOTICE: credit upstream Jaspr projects; remove VS Code extension framing

## 0.1.1

- Remove `resolution: workspace` so the package installs cleanly from pub.dev / Lumide Marketplace

## 0.1.0

- Initial Lumide Jaspr plugin
- Project detection, doctor/clean/create
- Serve via `jaspr daemon` with output channel and status bar
- Dual Server + Client VM debug attach
- Launch provider with `type: jaspr` config import
