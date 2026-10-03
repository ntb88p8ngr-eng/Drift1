@echo off
rem Midnight Drift dedicated server: runs in this console window, settings in server.cfg (created on first start).
cd /d "%~dp0"
MidnightDriftServer.console.exe --headless -- --server %*
pause
