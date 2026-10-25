param(
  [switch]$Relaunch
)

$ErrorActionPreference = 'Stop'

$src = 'D:\AI\nai\Aaalice_NAI_Launcher-main\build\windows\x64\runner\Release'
$dst = 'D:\AI\nai\NAI_Launcher_Windows_4.3.0+45_Portable'
$buildAppSo = 'D:\AI\nai\Aaalice_NAI_Launcher-main\build\windows\app.so'
$buildAssets = 'D:\AI\nai\Aaalice_NAI_Launcher-main\build\flutter_assets'

# Close existing launcher if running so files can be replaced cleanly
$procs = Get-Process -Name 'nai_launcher' -ErrorAction SilentlyContinue
if ($procs) {
  foreach ($p in $procs) {
    Stop-Process -Id $p.Id -Force
  }
  Start-Sleep -Seconds 1
}

# Ensure data directories exist
New-Item -ItemType Directory -Force -Path (Join-Path $src 'data') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dst 'data') | Out-Null

# Fresh build sync if built via flutter assemble
if (Test-Path -LiteralPath $buildAppSo) {
  New-Item -ItemType Directory -Force -Path (Join-Path $src 'windows') | Out-Null
  Copy-Item -LiteralPath $buildAppSo -Destination (Join-Path $src 'windows\app.so') -Force
}
if (Test-Path -LiteralPath $buildAssets) {
  New-Item -ItemType Directory -Force -Path (Join-Path $src 'flutter_assets') | Out-Null
  Copy-Item -Path (Join-Path $buildAssets '*') -Destination (Join-Path $src 'flutter_assets') -Recurse -Force
}

# Copy to Release/data
Copy-Item -LiteralPath (Join-Path $src 'windows\app.so') -Destination (Join-Path $src 'data\app.so') -Force
Copy-Item -Path (Join-Path $src 'flutter_assets\*') -Destination (Join-Path $src 'data\flutter_assets') -Recurse -Force

# Copy to Portable/data
Copy-Item -LiteralPath (Join-Path $src 'windows\app.so') -Destination (Join-Path $dst 'data\app.so') -Force
Copy-Item -Path (Join-Path $src 'flutter_assets\*') -Destination (Join-Path $dst 'data\flutter_assets') -Recurse -Force

# Clean any nested flutter_assets directory if present
$nested = Join-Path $dst 'data\flutter_assets\flutter_assets'
if (Test-Path -LiteralPath $nested) {
  Remove-Item -LiteralPath $nested -Recurse -Force
}

# Update manifest
$manifestPath = Join-Path $dst 'app_files_manifest.json'
$managedFiles = Get-ChildItem -LiteralPath $dst -File -Recurse |
  Where-Object { 
    $_.FullName -notmatch '\\cache\\' -and 
    $_.Extension -ne '.log' -and 
    $_.Extension -ne '.txt' -and 
    $_.Extension -ne '.old_upgrade' -and
    $_.FullName -notmatch '\\nai_launcher\.exe\.WebView2\\' -and
    $_.Name -ne 'app_files_manifest.json' 
  } |
  ForEach-Object {
    $_.FullName.Substring($dst.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
  } |
  Sort-Object

$manifest = [ordered]@{
  schemaVersion = 1
  version = '4.3.1-safe'
  files = @($managedFiles)
}

$manifestJson = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.Encoding]::UTF8)

Write-Host "Deployment complete."
Get-Item (Join-Path $dst 'data\app.so') | Select-Object FullName, Length, LastWriteTime

if ($Relaunch) {
  Write-Host "Relaunching portable nai_launcher.exe..."
  ([wmiclass]"win32_process").Create((Join-Path $dst 'nai_launcher.exe'), $dst, $null) | Out-Null
}
