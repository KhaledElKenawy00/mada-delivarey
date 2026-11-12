#!/usr/bin/env bash
# تثبيت مدار على Linux: بينسخ التطبيق لمجلد المستخدم ويضيفه لقائمة التطبيقات بأيقونته.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/madar"

mkdir -p "$DEST"
cp -r "$DIR/bundle/." "$DEST/"
cp "$DIR/madar.png" "$DEST/madar.png"
chmod +x "$DEST/madar"

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/madar.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=مدار
Name[en]=Madar
Comment=نظام إدارة التوزيع والمبيعات الميدانية
Exec=$DEST/madar
Icon=$DEST/madar.png
Path=$DEST
Terminal=false
Categories=Office;Business;
EOF

update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

echo "اتثبت مدار في: $DEST"
echo "هتلاقيه في قائمة التطبيقات، أو شغّله على طول بـ: $DEST/madar"
