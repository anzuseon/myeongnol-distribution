@echo off
setlocal
cd /d "%~dp0"

echo Myeongnol modpack publishing started.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-modpack.ps1" %*
set "publishExitCode=%ERRORLEVEL%"

echo.
if not "%publishExitCode%"=="0" (
    echo Publishing failed. Review the error above.
) else (
    echo Publishing finished successfully.
)

pause
exit /b %publishExitCode%
