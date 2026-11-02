@echo off
title Moodle MBZ downloader
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download-all.ps1"
echo.
pause
