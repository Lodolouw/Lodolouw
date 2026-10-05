@echo off
rem ------------------------------------------------------------------
rem  Feed the Thing in the Basement - upload to Roblox
rem
rem  Double-click this file. It asks for your Roblox API key and your
rem  user id, uploads whatever is new or changed (the sounds, the map,
rem  the props) and writes their ids into the game's files. Rojo then
rem  puts them in Studio. Commit and push in GitHub Desktop afterwards.
rem
rem  The first time, it downloads a small Python (only used by this
rem  file) into the .tools folder next to it.
rem
rem  upload.bat forget    forgets the key saved on this computer
rem ------------------------------------------------------------------
cd /d "%~dp0"
set "PY_VERSION=3.12.10"
set "PY_SHA256=4ACBED6DD1C744B0376E3B1CF57CE906F9DC9E95E68824584C8099A63025A3C3"
set "TOOLS=%~dp0.tools"
set "PYDIR=%TOOLS%\python"
set "PY=%PYDIR%\python.exe"

if not exist "%PY%" (
	echo Downloading Python %PY_VERSION% for the uploader - one time only...
	if not exist "%TOOLS%" mkdir "%TOOLS%"
	powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; $zip=Join-Path $env:TOOLS 'python.zip'; Invoke-WebRequest -Uri ('https://www.python.org/ftp/python/'+$env:PY_VERSION+'/python-'+$env:PY_VERSION+'-embed-amd64.zip') -OutFile $zip; if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $env:PY_SHA256) { Remove-Item $zip; Write-Host 'The download did not match its checksum, so it was deleted.'; exit 1 }; Expand-Archive -Force -Path $zip -DestinationPath $env:PYDIR; Remove-Item $zip; Get-ChildItem $env:PYDIR | Unblock-File"
)
if not exist "%PY%" (
	echo.
	echo Couldn't download Python. Check your internet and try again.
	pause
	exit /b 1
)

set "MODE=--ask"
if /i "%~1"=="forget" set "MODE=--forget"
echo.
"%PY%" -X utf8 Tools\upload_assets.py %MODE%
echo.
pause
