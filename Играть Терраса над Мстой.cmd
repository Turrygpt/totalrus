@echo off
cd /d "%~dp0"
set "PATCHED_GODOT=%~dp0Godot_v4.7.2-texture-thread_win64.exe"
if exist "%PATCHED_GODOT%" (
    start "" "%PATCHED_GODOT%" --path "%~dp0." --render-thread separate res://scenes/tactical_maps/msta_battlefield.tscn
) else (
    start "" "%~dp0Godot_v4.7.2-stable_win64.exe" --path "%~dp0." res://scenes/tactical_maps/msta_battlefield.tscn
)
