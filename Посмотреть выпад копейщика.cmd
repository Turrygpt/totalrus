@echo off
cd /d "%~dp0" || exit /b 1
start "" "%~dp0Godot_v4.7.2-stable_win64.exe" --path "%~dp0." --windowed --resolution 1280x720 res://scenes/spearman_attack_preview.tscn %*
