@echo off
setlocal
set "RESOLVER=%~dp0gradle\wrapper\run-gradle.ps1"
set "GRADLE_COMMAND="
for /f "usebackq delims=" %%G in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%RESOLVER%"`) do set "GRADLE_COMMAND=%%G"
if not defined GRADLE_COMMAND (
    echo Failed to locate or prepare a verified Gradle 8.12 installation.
    exit /b 1
)
call "%GRADLE_COMMAND%" %*
exit /b %ERRORLEVEL%
