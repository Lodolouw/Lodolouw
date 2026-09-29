@echo off
rem Double-click me: uploads every animation in upload\ and puts the IDs in Config.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_animations.ps1"
pause
