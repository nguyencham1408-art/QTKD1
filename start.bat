@echo off
chcp 65001 >nul
title AI Agent Dai Thanh - Localhost
echo ==============================================================================
echo   HE THONG AI AGENT THAM DINH DOI TAC PHAN PHOI - CONG TY GIA DUNG DAI THANH
echo ==============================================================
echo Dang khoi dong Web Server tai: http://localhost:5000 ...
echo Vui long giu cua so nay de duy tri may chu.
echo.
timeout /t 2 >nul
start http://localhost:5000
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 5000
pause

