#!/usr/bin/env bash
# Кооп-мод для «Неясного» (macOS). Двойной клик — установить, с аргументом uninstall — удалить.
# Игра не изменяется: рядом с исполняемым файлом кладётся override.cfg, скрипты — в папку данных игры.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Library/Application Support/Steam/steamapps/common/Neyasnoe/neyasnoe.app"
MODDIR="$HOME/Library/Application Support/Godot/app_userdata/Neyasnoe/mods"
MARK="; neyasnoe coop mod"

if [ ! -d "$APP" ]; then
  echo "Не найдена игра: $APP"
  echo "Перетащите neyasnoe.app в это окно и нажмите Enter (или Ctrl+C для отмены):"
  read -r APP
  APP="${APP%/}"; APP="${APP//\\ / }"; APP="${APP//\'/}"
  [ -d "$APP/Contents/MacOS" ] || { echo "Это не neyasnoe.app"; exit 1; }
fi
OVERRIDE="$APP/Contents/MacOS/override.cfg"

if [ -f "$OVERRIDE" ] && ! grep -q "$MARK" "$OVERRIDE"; then
  echo "В папке игры уже есть чужой override.cfg — не трогаю: $OVERRIDE"; exit 1
fi

if [ "${1:-}" = "uninstall" ]; then
  rm -f "$OVERRIDE" "$MODDIR"/coop*.gd
  echo "Готово: мод удалён."
  exit 0
fi

mkdir -p "$MODDIR"
cp "$HERE"/coop_mod/*.gd "$MODDIR/"
printf '%s\n[autoload]\n\nCoopMod="*user://mods/coop.gd"\n' "$MARK" > "$OVERRIDE"
echo "Готово: мод установлен. В главном меню появится «игра с друзьями»."
