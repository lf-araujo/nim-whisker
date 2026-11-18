#!/bin/sh
# Starts the menu preview in the isolated test session, with a fake default
# app for text files (so Open / Open With can be checked without launching a
# real program: the app appends the file's URI to $TESTDIR/opened.txt).
# Usage: tests/start-preview.sh [SECONDS]   (default lifetime 600)
here=$(cd "$(dirname "$0")" && pwd)
. "$here/env.sh" || exit 1
t=$TESTDIR; mkdir -p "$t/config" "$t/data/applications"
cat > "$t/opener.sh" <<EOT
#!/bin/sh
echo "\$1" >> $t/opened.txt
EOT
chmod +x "$t/opener.sh"
cat > "$t/data/applications/whisker-test-opener.desktop" <<EOT
[Desktop Entry]
Type=Application
Name=Whisker Test Opener
Exec=$t/opener.sh %u
MimeType=text/plain;text/markdown;
Icon=text-x-generic
EOT
printf '[Default Applications]\ntext/plain=whisker-test-opener.desktop\ntext/markdown=whisker-test-opener.desktop\n[Added Associations]\ntext/plain=whisker-test-opener.desktop;\ntext/markdown=whisker-test-opener.desktop;\n' > "$t/config/mimeapps.list"
rm -f "$t/opened.txt"
XDG_CONFIG_HOME=$t/config XDG_DATA_HOME=$t/data timeout "${1:-600}" \
  "$here/../build/whisker-preview" --stay $PREVIEW_OPTS --base:/plugins/plugin-5 >"$t/preview.log" 2>&1 &
