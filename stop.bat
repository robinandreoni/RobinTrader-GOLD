@echo off
title RobinTrader GOLD - Stop Fleet
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_fleet.ps1"
pause
