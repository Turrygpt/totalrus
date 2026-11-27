@echo off
cd /d "%~dp0"
start "" "Godot_v4.7.2-stable_win64.exe" --path . --windowed --resolution 1440x1000 scenes/prince_preview.tscn
