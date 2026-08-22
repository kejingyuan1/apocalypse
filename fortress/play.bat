@echo off
REM ============================================================
REM  Apocalypse Fortress - one-click launcher
REM  Double-click to play. Optional args:
REM    play.bat            -> play = attack mode, default
REM    play.bat editor     -> open Godot editor
REM    play.bat import     -> headless resource import, run once after clone/pull
REM
REM  WHY THE AUTO-REIMPORT:
REM  Godot does NOT auto-import assets in plain "--path" (game) mode.
REM  If you pull new art and the game flashes closed on launch, it is
REM  almost always a missing .ctex import cache on your machine. This
REM  launcher re-imports automatically whenever the repo HEAD changed
REM  (or the cache is missing), so just re-running play.bat fixes it.
REM ============================================================
setlocal
set "GAMEDIR=%~dp0"
if "%GAMEDIR:~-1%"=="\" set "GAMEDIR=%GAMEDIR:~0,-1%"

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

REM ---- auto re-import when needed (repo HEAD changed or cache missing) ----
set "CURHEAD="
for /f "usebackq delims=" %%g in (`git -C "%GAMEDIR%" rev-parse --short HEAD 2^>nul`) do set "CURHEAD=%%g"
set "LASTHEAD="
if exist "%GAMEDIR%\.godot\.import_head" (
  for /f "usebackq delims=" %%h in ("%GAMEDIR%\.godot\.import_head") do set "LASTHEAD=%%h"
)
set "NEED_IMPORT=0"
if not exist "%GAMEDIR%\.godot\imported" set "NEED_IMPORT=1"
if not "%CURHEAD%"=="%LASTHEAD%" set "NEED_IMPORT=1"

if "%NEED_IMPORT%"=="1" (
  echo [setup] Importing resources (first launch / assets changed) ...
  "%GODOT%" --headless --editor --quit --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
  if not "%CURHEAD%"=="" echo %CURHEAD% > "%GAMEDIR%\.godot\.import_head"
)

echo Launching Apocalypse Fortress ...
"%GODOT%" --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
if errorlevel 1 (
  echo.
  echo [ERROR] Godot failed to start, exit code %errorlevel%. See godot_run.log
  echo If it flashed closed, run:  play.bat import   then   play.bat
  pause
)

endlocal
