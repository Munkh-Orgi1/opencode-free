@echo off
setlocal
set "SRC=%~dp0OpenCode Free.bat"
if not exist "%SRC%" (
  echo [err] OpenCode Free.bat not found next to this installer
  pause
  exit /b 1
)
copy /y "%SRC%" "%USERPROFILE%\Desktop\OpenCode Free.bat" >nul
if errorlevel 1 (
  echo [err] could not copy to Desktop
  pause
  exit /b 1
)
echo installed to %USERPROFILE%\Desktop\OpenCode Free.bat
echo double-click it to start OpenCode through WARP
pause
