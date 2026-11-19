@echo off
title RobinTrader GOLD - Account Status
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_status.ps1"
