# Downloads the two big artifacts this spike needs (never committed):
#   cef_artifacts/  gdcef v0.17.0 Windows x64 (built vs Godot 4.3 -> loads on 4.4.1)
#   bin/            Godot 4.4.1-stable win64 editor/runtime (pinned engine)
# Idempotent: skips anything already in place. Run from anywhere.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tmp = Join-Path $env:TEMP "webview-latency-spike-dl"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$cefUrl = "https://github.com/Lecrapouille/gdcef/releases/download/v0.17.0-godot4/gdCEF-0.17.0_Godot-4.3_Windows_X64.tar.gz"
$godotUrl = "https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_win64.exe.zip"

# --- gdcef CEF artifacts (~148MB download) ---
if (Test-Path "$root\cef_artifacts\libgdcef.dll") {
    Write-Host "cef_artifacts already present, skipping"
} else {
    $tar = Join-Path $tmp "gdcef-win64.tar.gz"
    if (!(Test-Path $tar)) {
        Write-Host "downloading gdcef v0.17.0 win64 (~148MB)..."
        Invoke-WebRequest -Uri $cefUrl -OutFile $tar
    }
    $ext = Join-Path $tmp "extract"
    if (Test-Path $ext) { Remove-Item -Recurse -Force $ext }
    New-Item -ItemType Directory -Force -Path $ext | Out-Null
    Write-Host "extracting..."
    tar -xf $tar -C $ext
    $dll = Get-ChildItem -Recurse -Path $ext -Filter "libgdcef.dll" | Select-Object -First 1
    if ($null -eq $dll) { throw "libgdcef.dll not found in archive - layout changed?" }
    Copy-Item -Recurse -Force $dll.DirectoryName "$root\cef_artifacts"
    Write-Host "cef_artifacts installed"
}

# --- Godot 4.4.1 pinned engine (~60MB download) ---
if (Test-Path "$root\bin\Godot_v4.4.1-stable_win64.exe") {
    Write-Host "Godot 4.4.1 already present, skipping"
} else {
    $zip = Join-Path $tmp "godot-4.4.1.zip"
    if (!(Test-Path $zip)) {
        Write-Host "downloading Godot 4.4.1 win64..."
        Invoke-WebRequest -Uri $godotUrl -OutFile $zip
    }
    New-Item -ItemType Directory -Force -Path "$root\bin" | Out-Null
    Expand-Archive -Path $zip -DestinationPath "$root\bin" -Force
    Write-Host "Godot 4.4.1 installed to bin\"
}

Write-Host ""
Write-Host "done. run with:  bin\Godot_v4.4.1-stable_win64.exe --path ."
