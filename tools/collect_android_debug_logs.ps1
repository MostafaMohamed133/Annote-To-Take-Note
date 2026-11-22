param(
    [string]$DeviceId = "RFCWC1GD4QX",
    [string]$OutputFile = "road_guard_android_logcat.txt"
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { throw 'adb.exe not found. Check Android SDK Platform-Tools installation.' }
    $adb = $cmd.Source
}

& $adb -s $DeviceId get-state
if ($LASTEXITCODE -ne 0) { throw "Device $DeviceId is not available through ADB." }

$fullPath = Join-Path (Get-Location) $OutputFile
& $adb -s $DeviceId logcat -d -v threadtime | Out-File -FilePath $fullPath -Encoding utf8
Write-Host "Saved full Android logcat to: $fullPath"
Write-Host "Relevant Road Guard / Flutter errors:"
Get-Content $fullPath | Select-String -Pattern 'FATAL EXCEPTION|AndroidRuntime|ROAD_GUARD_|RoadGuardAnnotator|DartVM|FlutterJNI|flutter.*(error|exception)|Fatal signal|SIGABRT|SIGSEGV'
