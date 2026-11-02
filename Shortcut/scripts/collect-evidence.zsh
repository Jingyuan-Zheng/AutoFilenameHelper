#!/bin/zsh
set -u

payload=$(/bin/cat)
quality=$(printf '%s\n' "$payload" | /usr/bin/grep -Eio 'meaningless|ambiguous|meaningful' | /usr/bin/tail -1)
[[ "$quality" == "ambiguous" || "$quality" == "meaningless" ]] || exit 0

path_b64=$(printf '%s\n' "$payload" | /usr/bin/sed -n 's/^PATH_B64=//p' | /usr/bin/head -1)
[[ -n "$path_b64" ]] || exit 0
path=$(printf '%s' "$path_b64" | /usr/bin/base64 -D 2>/dev/null) || exit 0
[[ -e "$path" && ! -L "$path" ]] || exit 0
[[ -f "$path" || -d "$path" ]] || exit 0

if [[ -d "$path" ]]; then
  item_type="directory"
else
  item_type="file"
fi

name="${path:t}"
lower="${name:l}"
size=$(/usr/bin/stat -f '%z' "$path" 2>/dev/null || print 0)
mime=$(/usr/bin/file -b --mime-type "$path" 2>/dev/null || print unknown)
description=$(/usr/bin/file -b "$path" 2>/dev/null || print unknown)

mode=TEXT
case "$mime" in image/*) (( size <= 52428800 )) && mode=IMAGE ;; esac

print 'STATE=EVIDENCE_READY'
print "ITEM_TYPE=$item_type"
print "ANALYSIS_MODE=$mode"
print "INITIAL_QUALITY=$quality"
print "PATH_B64=$path_b64"
print "CURRENT_FILENAME=$name"
print "FILE_SIZE_BYTES=$size"
print "MIME_TYPE=$mime"
print "FILE_DESCRIPTION=$description"

print '\n--- SPOTLIGHT METADATA ---'
/usr/bin/mdls \
  -name kMDItemWhereFroms \
  -name kMDItemContentType \
  -name kMDItemKind \
  -name kMDItemTitle \
  -name kMDItemVersion \
  -name kMDItemAuthors \
  -name kMDItemDownloadedDate \
  -name kMDItemCFBundleIdentifier \
  -name kMDItemDurationSeconds \
  -name kMDItemPixelHeight \
  -name kMDItemPixelWidth \
  -name kMDItemAudioBitRate \
  -name kMDItemCodecs \
  "$path" 2>/dev/null | /usr/bin/head -c 20000

print '\n\n--- EXTENDED ATTRIBUTE NAMES ---'
/usr/bin/xattr "$path" 2>/dev/null | /usr/bin/head -100
print '\n--- QUARANTINE ATTRIBUTE (bounded) ---'
/usr/bin/xattr -p com.apple.quarantine "$path" 2>/dev/null | /usr/bin/head -c 4096

if [[ "$item_type" == "directory" ]]; then
  print '\n\n--- DIRECTORY CONTENTS (top level only) ---'
  /bin/ls -1A "$path" 2>/dev/null | /usr/bin/head -200 | /usr/bin/head -c 20000
  exit 0
fi

case "$lower" in
  *.zip)
    print '\n\n--- ARCHIVE DIRECTORY LISTING (no extraction) ---'
    /usr/bin/unzip -Z1 "$path" 2>/dev/null | /usr/bin/head -200 | /usr/bin/head -c 20000
    ;;
  *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tar.xz)
    print '\n\n--- ARCHIVE DIRECTORY LISTING (no extraction) ---'
    /usr/bin/tar -tf "$path" 2>/dev/null | /usr/bin/head -200 | /usr/bin/head -c 20000
    ;;
  *.gz|*.bz2|*.xz)
    print '\n\n--- COMPRESSED FILE SUMMARY (no extraction) ---'
    case "$lower" in
      *.gz) /usr/bin/gzip -l "$path" 2>/dev/null ;;
      *) print 'The built-in tools identify this compressed stream; contents were not expanded.' ;;
    esac
    ;;
  *.docx|*.pptx|*.xlsx)
    print '\n\n--- OFFICE CORE PROPERTIES ---'
    /usr/bin/unzip -p "$path" docProps/core.xml 2>/dev/null | /usr/bin/head -c 10000 | /usr/bin/sed 's/<[^>]*>/ /g'
    print '\n--- OFFICE CONTENT SAMPLE ---'
    case "$lower" in
      *.docx) entry='word/document.xml' ;;
      *.pptx) entry=$(/usr/bin/unzip -Z1 "$path" 2>/dev/null | /usr/bin/grep '^ppt/slides/slide[0-9].*\.xml$' | /usr/bin/head -1) ;;
      *.xlsx) entry='xl/sharedStrings.xml' ;;
    esac
    [[ -n "${entry-}" ]] && /usr/bin/unzip -p "$path" "$entry" 2>/dev/null | /usr/bin/head -c 24000 | /usr/bin/sed 's/<[^>]*>/ /g'
    ;;
  *.pdf)
    print '\n\n--- SPOTLIGHT TEXT SAMPLE ---'
    /usr/bin/mdls -raw -name kMDItemTextContent "$path" 2>/dev/null | /usr/bin/head -c 24000
    ;;
  *.dmg)
    print '\n\n--- DISK IMAGE INFO (not mounted) ---'
    /usr/bin/hdiutil imageinfo "$path" 2>/dev/null | /usr/bin/head -c 16000
    print '\n--- SIGNATURE ASSESSMENT (not executed) ---'
    /usr/sbin/spctl -a -vv -t open --context context:primary-signature "$path" 2>&1 | /usr/bin/head -c 8000
    ;;
  *.pkg)
    print '\n\n--- INSTALLER SIGNATURE (not installed) ---'
    /usr/sbin/pkgutil --check-signature "$path" 2>&1 | /usr/bin/head -c 12000
    print '\n--- PAYLOAD FILE NAMES (not installed) ---'
    /usr/sbin/pkgutil --payload-files "$path" 2>/dev/null | /usr/bin/head -150 | /usr/bin/head -c 16000
    ;;
  *)
    case "$mime" in
      text/*|application/json|application/xml|application/javascript|application/x-shellscript)
        print '\n\n--- TEXT SAMPLE ---'
        /usr/bin/head -c 32000 "$path"
        ;;
      image/*)
        print '\n\n--- IMAGE PROPERTIES ---'
        /usr/bin/sips -g pixelWidth -g pixelHeight -g format -g profile "$path" 2>/dev/null | /usr/bin/head -c 8000
        (( size > 52428800 )) && print '\nImage exceeds 50 MB, so it will not be attached to the model.'
        ;;
      audio/*|video/*)
        print '\n\nMedia content is not transcribed. Use only the bounded metadata above.'
        ;;
      *)
        print '\n\n--- PRINTABLE METADATA SAMPLE ---'
        /usr/bin/strings -a "$path" 2>/dev/null | /usr/bin/head -120 | /usr/bin/head -c 12000
        ;;
    esac
    ;;
esac

exit 0
