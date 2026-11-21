@echo off
chcp 65001 >nul
title Personal AI OS Installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
