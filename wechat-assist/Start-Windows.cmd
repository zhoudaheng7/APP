@echo off
chcp 65001 >nul
title 知会 - Windows 微信助手
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Windows.ps1" -Phone -Background
if errorlevel 1 pause
