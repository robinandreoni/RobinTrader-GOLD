@echo off
title RobinTrader GOLD - Fleet Launcher
echo Starting RobinTrader GOLD Multi-Agent Fleet...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_fleet.ps1"
pause
