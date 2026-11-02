#!/bin/zsh
set -u

path="${1-}"
[[ -n "$path" ]] || exit 0
[[ -e "$path" && ! -L "$path" ]] || exit 0
[[ -f "$path" || -d "$path" ]] || exit 0

name="${path:t}"
[[ "$name" != .* ]] || exit 0
lower="${name:l}"
case "$lower" in
  *.download|*.crdownload|*.part|*.tmp|*.partial) exit 0 ;;
esac

before=$(/usr/bin/stat -f '%z|%m' "$path" 2>/dev/null) || exit 0
/bin/sleep 3
[[ -e "$path" && ! -L "$path" ]] || exit 0
[[ -f "$path" || -d "$path" ]] || exit 0
after=$(/usr/bin/stat -f '%z|%m' "$path" 2>/dev/null) || exit 0
[[ "$before" == "$after" ]] || exit 0

size=${after%%|*}
created_epoch=$(/usr/bin/stat -f '%B' "$path" 2>/dev/null || print 0)
modified_epoch=${after#*|}
created=$(/bin/date -r "$created_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || print unknown)
modified=$(/bin/date -r "$modified_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || print unknown)

if [[ -d "$path" ]]; then
  item_type="directory"
  case "$lower" in
    *.app|*.bundle|*.framework|*.plugin|*.kext) suffix=".${name##*.}" ;;
    *) suffix="" ;;
  esac
else
  item_type="file"
  case "$lower" in
    *.tar.gz) suffix="${name[-7,-1]}" ;;
    *.tar.bz2) suffix="${name[-8,-1]}" ;;
    *.tar.xz) suffix="${name[-7,-1]}" ;;
    *)
      if [[ "$name" == *.* ]]; then suffix=".${name##*.}"; else suffix=""; fi
      ;;
  esac
fi

path_b64=$(printf '%s' "$path" | /usr/bin/base64 | /usr/bin/tr -d '\n')
printf '%s\n' \
  'STATE=READY' \
  "ITEM_TYPE=$item_type" \
  "PATH_B64=$path_b64" \
  "CURRENT_FILENAME=$name" \
  "ORIGINAL_EXTENSION=$suffix" \
  "FILE_SIZE_BYTES=$size" \
  "CREATED_DATE=$created" \
  "MODIFIED_DATE=$modified"
