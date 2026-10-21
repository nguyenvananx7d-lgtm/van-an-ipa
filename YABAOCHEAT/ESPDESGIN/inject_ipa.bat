@echo off
chcp 65001 >nul
title Free Fire ESP - IPA Injector
cd /d "%~dp0"

echo =======================================================
echo          FREE FIRE ESP - 1-CLICK IPA INJECTOR         
echo =======================================================
echo.

set PYTHON_CMD=py
py --version >nul 2>&1
if %errorlevel% neq 0 (
    set PYTHON_CMD=python
    python --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo [!] Lỗi: Không tìm thấy Python trên máy tính.
        pause
        exit /b 1
    )
)

%PYTHON_CMD% tools\inject_ipa.py %*

echo.
pause
