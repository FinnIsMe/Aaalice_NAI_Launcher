$ErrorActionPreference = 'Stop'
$env:FLUTTER_ROOT = 'E:\flutter'
$env:PROJECT_DIR = 'D:\AI\nai\Aaalice_NAI_Launcher-main'
$env:TRACK_WIDGET_CREATION = 'false'
$env:TREE_SHAKE_ICONS = 'false'
$env:Path = "E:\flutter\bin;" + $env:Path
Set-Location 'D:\AI\nai\Aaalice_NAI_Launcher-main'

Write-Host "Compiling release Windows assets and app.so..."
& "E:\flutter\packages\flutter_tools\bin\tool_backend.bat" windows-x64 release
if ($LASTEXITCODE -ne 0) {
    Write-Error "tool_backend.bat failed with code $LASTEXITCODE"
}
Write-Host "Compilation finished successfully."
