@echo off
chcp 65001 >nul
rem Удаляет кооп-мод «Неясного». Запускать из папки игры, рядом с neyasnoe.exe.
if exist "%~dp0override.cfg" findstr /C:"neyasnoe coop mod" "%~dp0override.cfg" >nul && del "%~dp0override.cfg"
del /Q "%APPDATA%\Godot\app_userdata\Neyasnoe\mods\coop*.gd" 2>nul
echo Готово: мод удалён.
pause
