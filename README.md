# Auto Filename Helper

[简体中文](README.zh-CN.md)

A native macOS companion for a Finder Shortcut that suggests informative filenames. The Shortcut classifies the existing name and asks a model for a factual suggestion; the app validates the request, preserves extensions, and handles confirmation and non-overwriting renames.

![Auto Filename confirmation: original name, suggested name, confidence, and reason](docs/images/rename-confirmation.png)

## Install and use

1. Download or clone this repository. The helper requires macOS 13 or later and Xcode Command Line Tools to build.
2. Run **Install.command**, or run **build_and_install.sh** with zsh from the project folder. The app is installed in the current user’s Applications folder as **AutoFilenameHelper.app**.
3. Download and open [Auto Filename.shortcut](https://github.com/Jingyuan-Zheng/AutoFilenameHelper/raw/refs/heads/main/Auto%20Filename.shortcut). Inspect its actions, then add it to Shortcuts. The included file already calls the installed app; no username or path editing is required for the default installation.
4. The complete Shortcut requires a Mac and macOS version that support the **Use Model** action, with Apple Intelligence and the ChatGPT model available. The native helper’s macOS 13 minimum does not mean the AI Shortcut works on macOS 13. Review the model choice and any permission prompts in Shortcuts.
5. Select a disposable file copy in Finder and run **Quick Actions → Auto Filename**. If it is absent, enable the Shortcut for Finder in its details. Allow running scripts in Shortcuts if macOS requests it.
6. Review the native confirmation window when shown. High-confidence suggestions can rename automatically according to your settings; a meaningful original name is deliberately left alone.

If an older Shortcut has the same name, remove or rename it before importing this file. Opening the app directly displays its settings; it does not generate a filename suggestion.

## Behaviour

- Preserves the original extension by default and avoids overwriting existing files.
- Rejects unsafe names, symlinks, unsupported source types, and unchanged names.
- Can require confirmation for ambiguous names, low confidence, executables, or disabled automatic renaming.
- Includes Quick Look, Reveal in Finder, Copy Path, conflict strategies, appearance settings, and English/Simplified Chinese interfaces.
- The launcher uses the current user’s home directory and gives an error if the helper is missing. For a custom install location, update the last shell action.

## Workflow details and troubleshooting

Read the [illustrated English guide, complete key scripts, and model prompts](https://jingyuan.is-a.dev/p/auto-filename-helper/) or the [中文教程](https://jingyuan.is-a.dev/zh/p/auto-filename-helper/). The article explains the input contract, why a run may leave a name unchanged, and how the prompt wiring was repaired.

The editable [Shortcut source](Shortcut/Auto%20Filename.xml), [shell scripts](Shortcut/scripts/), and [prompt files](Shortcut/prompts/) are included for inspection and modification. The signed file is the ready-to-import download. Editing the source requires re-signing before import; the blog documents that process.

## Privacy and licence

The helper itself does not make network requests. The Shortcut uses Apple Intelligence for name classification and ChatGPT for suggestions; bounded file text, metadata, and supported images may be sent to the selected model service. Its model actions also allow web search. Review the workflow and provider settings before using private documents. A confidence score comes from the model and is not an independent accuracy guarantee.

Project source, Shortcut, scripts, prompts, and documentation are available under the [MIT licence](LICENSE). The build uses macOS’s Finder icon locally; Apple system assets and third-party services remain subject to their own terms.
