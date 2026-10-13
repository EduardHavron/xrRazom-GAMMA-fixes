@echo off
rem xrRazom fixes: remove the auto-updater (installed mods are kept)
rem single line on purpose: this .bat may be deleted while it runs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_agent.ps1" %* & pause & exit /b
