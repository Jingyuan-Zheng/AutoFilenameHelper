#!/bin/zsh
set -e
ROOT_DIR="${0:A:h}"
cd "$ROOT_DIR"
exec ./build_and_install.sh
