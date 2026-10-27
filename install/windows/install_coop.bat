@echo off
chcp 65001 >nul
rem Кооп-мод для «Неясного». Скопируйте ВСЁ содержимое этой папки туда, где лежит neyasnoe.exe,
rem и запустите этот файл. Игра не изменяется; удалить мод = удалить override.cfg.
if not exist "%~dp0neyasnoe.exe" (
  echo Не найден neyasnoe.exe рядом с этим файлом. Скопируйте папку в папку игры.
  pause
  exit /b 1
)
set "DST=%APPDATA%\Godot\app_userdata\Neyasnoe\mods"
if not exist "%DST%" mkdir "%DST%"
copy /Y "%~dp0coop_mod\*.gd" "%DST%\" >nul
echo Готово: мод установлен. F9 - позвать друга, Enter - чат.
pause
