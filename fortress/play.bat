@echo off
REM ============================================================
REM  Apocalypse Fortress - one-click launcher
REM  Double-click to play. Optional args:
REM    play.bat            -> play = attack mode, default
REM    play.bat editor     -> open Godot editor
REM    play.bat import     -> headless resource import, run once after clone
REM ============================================================
setlocal

REM project dir = folder of this script
set "GAMEDIR=%~dp0"
if "%GAMEDIR:~-1%"=="\" set "GAMEDIR=%GAMEDIR:~0,-1%"

REM Godot executable (override via env var GODOT_EXE if your path differs)
if defined GODOT_EXE (set "GODOT=%GODOT_EXE%") else (
  set "GODOT=D:\360Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"
)

if not exist "%GODOT%" (
  echo [ERROR] Godot executable not found:
  echo   %GODOT%
  echo.
  echo Install Godot 4.6 stable, or set env var GODOT_EXE to its path.
  pause
  exit /b 1
)

title Apocalypse Fortress

if "%~1"=="editor" (
  echo Opening Godot editor ...
  "%GODOT%" --editor --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
  goto :eof
)

if "%~1"=="import" (
  echo Importing resources, headless mode ...
  "%GODOT%" --headless --editor --quit --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
  echo Import done.
  goto :eof
)

echo Launching Apocalypse Fortress ...
"%GODOT%" --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
if errorlevel 1 (
  echo.
  echo [ERROR] Godot failed to start, exit code %errorlevel%. See godot_run.log
  pause
)

endlocal
