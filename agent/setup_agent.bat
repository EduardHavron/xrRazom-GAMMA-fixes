@echo off
rem xrRazom fixes: one-time setup of the auto-updater (no admin needed)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_agent.ps1" %*
pause
