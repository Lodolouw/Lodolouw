@echo off
rem Double-click me: uploads the weapon models and ability animations to Roblox
rem (with your Open Cloud API key) and copies their IDs for you to paste to Claude.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_assets.ps1"
pause
