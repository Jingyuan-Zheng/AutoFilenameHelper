AutoFilenameHelper 1.0.6

Auto Filename Helper
====================

What this package does
----------------------
This is a native macOS AppKit replacement for the existing zsh post-processing script.
It keeps the same stdin payload keys:

PATH_B64=
INITIAL_QUALITY=
suggestedFilename:
confidence:
reason:

Default behavior remains compatible with the original script:
- Only processes INITIAL_QUALITY=ambiguous or meaningless.
- Confidence must resolve to an integer from 60 through 100.
- Rejects missing paths, symlinks, unsupported path types, hidden/unsafe filenames, and unchanged names.
- By default, requires confirmation for ambiguous names, confidence below 95%, and executable/script-like files.
- Uses Finder's current file icon in the confirmation UI.
- By default, preserves the original extension while editing.
- Existing target names default to Name 2.ext, Name 3.ext, and so on.
- Revalidates the source and destination immediately before moving.
- Uses a normal non-overwriting FileManager move.

Version 1.0.6 changes
---------------------
- Removes the visible Auto Filename title from the Settings title bar.
- Removes the deprecated NSBox.borderType usage that produced compile warnings.
- Shows why confirmation is required (low confidence, ambiguous filename, executable/script, or auto rename disabled).
- Adds keyboard controls: Return = Rename, Escape = Keep Original/Cancel edit, Command-E = Edit Name, Space = Quick Look.
- Adds native Quick Look using QLPreviewPanel.
- Adds file-icon context actions: Quick Look, Show in Finder, and Copy Path.
- Serializes simultaneous confirmation requests across multiple Shortcut invocations so confirmation windows do not overlap.
- Adds conflict handling choices: Add a number, Add a timestamp, or Cancel the rename.
- Makes maximum filename length adjustable from 1 to 255 characters.
- Makes preservation of the original extension configurable.
- Adds standard .lproj localization resources for English and Simplified Chinese, plus System Default / English / Simplified Chinese selection.
- Adds Follow System / Light / Dark appearance selection.
- Settings remain immediate-apply; no Save or Apply button is used.

Install
-------
1. Open Terminal in this folder.
2. Run:

   ./build_and_install.sh

The app is installed to:

   /Users/jingyuan/Applications/AutoFilenameHelper.app

Shortcuts replacement
---------------------
Replace the previous long shell block with the contents of:

   shortcut_shell_replacement.sh

or simply:

   exec "/Users/jingyuan/Applications/AutoFilenameHelper.app/Contents/MacOS/AutoFilenameHelper"

Keep the Shortcuts action configured to pass its existing input to stdin.

Manual launch
-------------
Opening AutoFilenameHelper.app directly shows a small welcome window with access to Settings.
When invoked by Shortcuts with a valid high-confidence safe payload, it renames silently and exits.
When confirmation is required, it opens the native frosted confirmation window, then exits after the choice is handled.

Icon
----
The installer copies the icon from:
/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns
