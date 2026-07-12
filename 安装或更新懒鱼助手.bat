@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lazyfish-windows.ps1" deploy
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo 执行失败，请保留本窗口中的错误信息并联系卖家。
pause
exit /b %EXIT_CODE%
