@echo off
REM Starts Rojo: keep this window open while you work in Studio.
REM In Studio: Plugins tab, Rojo, Connect.
cd /d "%~dp0"
rojo serve
pause
