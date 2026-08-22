@echo off
REM ============================================================
REM  末日堡垒 (Apocalypse Fortress) 一键启动脚本
REM  双击本文件即可直接运行游戏；或在命令行附加参数：
REM    play.bat            -> 直接开玩（进攻模式，默认）
REM    play.bat editor     -> 打开 Godot 编辑器
REM    play.bat import     -> 仅执行资源导入（无头），用于首次克隆后修复贴图
REM ------------------------------------------------------------
REM  若 Godot 路径不同，可设置环境变量 GODOT_EXE 指向 4.6 可执行文件。
REM ============================================================
setlocal

REM 项目目录 = 本脚本所在目录
set "GAMEDIR=%~dp0"
REM 去掉末尾反斜杠：否则 "--path "路径\"" 中末尾 \" 会被 cmd 误判为转义引号，
REM 导致 Godot 收不到正确的项目目录而启动即退出（表现为双击闪退）
if "%GAMEDIR:~-1%"=="\" set "GAMEDIR=%GAMEDIR:~0,-1%"

REM Godot 可执行文件（默认路径，可用环境变量覆盖）
if defined GODOT_EXE (set "GODOT=%GODOT_EXE%") else (
  set "GODOT=D:\360Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"
)

if not exist "%GODOT%" (
  echo [错误] 找不到 Godot 可执行文件：
  echo   %GODOT%
  echo.
  echo 请先安装 Godot 4.6 stable，或设置环境变量 GODOT_EXE 指向它。
  pause
  exit /b 1
)

title 末日堡垒 - Apocalypse Fortress
cls

if "%~1"=="editor" (
  echo 正在打开 Godot 编辑器 ...
  "%GODOT%" --editor --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
  goto :eof
)

if "%~1"=="import" (
  echo 正在无头导入资源（首次克隆后执行一次即可） ...
  "%GODOT%" --headless --editor --quit --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
  echo 导入完成。
  goto :eof
)

echo 正在启动《末日堡垒》...
REM 同步直接运行（不用 start，避免 cmd 对带引号路径+参数的解析坑导致拉不起 Godot）
"%GODOT%" --path "%GAMEDIR%" > "%GAMEDIR%\godot_run.log" 2>&1
if errorlevel 1 (
  echo.
  echo [错误] Godot 启动失败（退出码 %errorlevel%），详情见 godot_run.log
  pause
)

endlocal
