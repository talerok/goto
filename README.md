# Goto

Minimalist file manager for macOS with a keyboard-first workflow and an editable address bar.

## Features

- **Editable address bar** with Tab-completion and autocomplete suggestions
- **Keyboard navigation** — arrow keys, type-ahead search, Enter to open, Space for Quick Look
- **Back / Forward / Up** navigation with history (Cmd+[, Cmd+], Cmd+Up)
- **Sortable columns** — name, date modified, size (directories always first)
- **In-folder search** (Cmd+F) — real-time filename filtering
- **Hidden files toggle** (Cmd+Shift+.)
- **Quick Look** preview via Space
- **Inline rename** — select a file and rename from context menu or F2
- **Copy & Paste** files (Cmd+C / Cmd+V)
- **Drag & Drop** — drag files out, drop files into folders
- **Context menu** — Open, Open With, Open in New Window, Reveal in Finder, Rename, Copy, Paste, Copy Path, Move to Trash, Get Info
- **Multi-window** — open directories in new windows
- **FSEvents monitoring** — directory contents update automatically
- **Path resolution** — supports `~`, `$ENV_VARS`, relative paths

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+L` | Focus address bar, select all |
| `Enter` | Open selected / navigate to path |
| `Esc` | Blur address bar, revert text |
| `Tab` | Autocomplete path |
| `Arrow Up/Down` | Navigate suggestions / file list |
| `Space` | Quick Look |
| `Delete` | Move to Trash |
| `Cmd+[` / `Cmd+]` | Back / Forward |
| `Cmd+Up` | Enclosing folder |
| `Cmd+F` | Search in folder |
| `Cmd+Shift+.` | Toggle hidden files |
| `Cmd+C` / `Cmd+V` | Copy / Paste files |
| `Cmd+Shift+C` | Copy path |
| `Cmd+A` | Select all |
| `Cmd+N` | New window |

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16.0+

## Build

```sh
brew install xcodegen   # if not installed
xcodegen generate
xcodebuild build -scheme Goto -destination 'platform=macOS'
```

## Architecture

SwiftUI with `@Observable` state management. NSTableView via NSViewRepresentable for the file list (sorting, inline rename, drag & drop). AppKit bridges for the address bar (NSTextField) and Quick Look (QLPreviewPanel). FSEvents for live directory monitoring.

```
Sources/
  GotoApp.swift              App entry, window, menu commands
  Models/                    FileItem, SortCriteria
  State/                     AppState, NavigationState, DirectoryState, AddressBarState
  Services/                  FileSystemService, PathResolver, FSEventsMonitor, IconProvider, QuickLookCoordinator
  Views/
    ContentView.swift        Main layout
    FileList/                NSTableView, search bar, context menu
    AddressBar/              TextField, autocomplete popover
```

## License

[MIT](LICENSE)
