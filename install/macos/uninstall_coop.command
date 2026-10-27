#!/usr/bin/env bash
# Удаляет кооп-мод «Неясного»: override.cfg из папки игры и скрипты из папки данных.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install_coop.command" uninstall
