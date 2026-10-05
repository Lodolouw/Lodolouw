@echo off
rem ------------------------------------------------------------------
rem  Feed the Thing in the Basement - start Rojo
rem
rem  Double-click this file, then in Roblox Studio open the Rojo panel
rem  and press Connect. Keep this window open while you work.
rem  The first time, it downloads Rojo 7.4.4 (matches your plugin) into
rem  the .tools folder next to this file.
rem ------------------------------------------------------------------
cd /d "%~dp0"
set "ROJO_VERSION=7.4.4"
set "TOOLS=%~dp0.tools"
set "ROJO=%TOOLS%\rojo.exe"

if not exist "%ROJO%" (
	echo Downloading Rojo %ROJO_VERSION% - one time only...
	if not exist "%TOOLS%" mkdir "%TOOLS%"
	powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; $zip=Join-Path $env:TOOLS 'rojo.zip'; Invoke-WebRequest -Uri ('https://github.com/rojo-rbx/rojo/releases/download/v'+$env:ROJO_VERSION+'/rojo-'+$env:ROJO_VERSION+'-windows-x86_64.zip') -OutFile $zip; Expand-Archive -Force -Path $zip -DestinationPath $env:TOOLS; Remove-Item $zip; Unblock-File (Join-Path $env:TOOLS 'rojo.exe')"
)
if not exist "%ROJO%" (
	echo.
	echo Couldn't download Rojo. Check your internet, or get rojo.exe from
	echo https://github.com/rojo-rbx/rojo/releases and put it in "%TOOLS%".
	pause
	exit /b 1
)

echo.
echo  Rojo is running for Feed the Thing in the Basement.
echo  In Roblox Studio: Rojo panel - Connect - Accept.
echo  Keep this window open while you work. Close it to stop.
echo.
"%ROJO%" serve default.project.json
pause
