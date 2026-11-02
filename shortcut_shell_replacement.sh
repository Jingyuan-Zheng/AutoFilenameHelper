#!/bin/zsh
set -eu
app="$HOME/Applications/AutoFilenameHelper.app/Contents/MacOS/AutoFilenameHelper"
if [[ ! -x "$app" ]]; then
  print -u2 'Auto Filename Helper is not installed. Build and install the app from https://github.com/Jingyuan-Zheng/AutoFilenameHelper first.'
  exit 1
fi
exec "$app"
