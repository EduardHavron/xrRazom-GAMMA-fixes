@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
set XRRFIX_RC=%errorlevel%
pause
exit /b %XRRFIX_RC%
