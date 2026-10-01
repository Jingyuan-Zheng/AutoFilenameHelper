# Auto Filename Helper

[简体中文](README.zh-CN.md)

Native macOS helper for a Shortcut-driven filename suggestion workflow. It validates input, preserves extensions by default, asks before risky renames, and uses non-overwriting moves.

## Build and install

```bash
./build_and_install.sh
```

The app is installed at `~/Applications/AutoFilenameHelper.app`. Configure `Auto Filename.shortcut` to send input to stdin.

## Use

1. Build and install the app.
2. Import `Auto Filename.shortcut` in Shortcuts and replace its execution step with `shortcut_shell_replacement.sh`.
3. Run the Shortcut from Finder on a file. Review the native confirmation window when one is shown.
4. Open the app directly to change language, appearance, rename threshold, extension handling, and conflict behaviour.

## Features

- Validates paths and rejects symlinks, hidden or unsafe names, unsupported file types, and unchanged names.
- Preserves the original extension by default and resolves name conflicts without overwriting files.
- Requires confirmation for ambiguous names, low confidence, executables, or disabled automatic rename.
- Provides Quick Look, Reveal in Finder, Copy Path, light/dark appearance, and English/Simplified Chinese settings.

## Shortcut contract

The helper reads a newline-delimited stdin payload containing `PATH_B64`, `INITIAL_QUALITY`, `suggestedFilename`, `confidence`, and `reason`. The Shortcut is responsible for deriving the suggestion; the app only validates and applies the rename.

## Requirements and privacy

macOS 13 or later and the Xcode Command Line Tools are required to build. Processing occurs locally; the helper does not make network requests. Review the Shortcut separately if it uses an AI service.
