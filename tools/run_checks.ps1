# Run all headless checks + python mirror. Engine auto-detected; override with $env:GODOT.
# Usage: .\tools\run_checks.ps1 [-Only rules,quality,...] [-Import]
param(
    [string]$Only = "",
    [switch]$Import
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Find-Engine {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $local = Join-Path $root "tools\godot_path.local"
    if (Test-Path $local) {
        $p = (Get-Content $local -Raw).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }
    $roots = @("$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE")
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        $hit = Get-ChildItem -Path $r -Filter "Godot_v*_console.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    foreach ($r in @("C:\Godot", "D:\Godot", "E:\github\tools")) {
        if (-not (Test-Path $r)) { continue }
        $hit = Get-ChildItem -Path $r -Filter "Godot_v*_console.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$engine = Find-Engine
if (-not $engine) {
    Write-Host "Godot console engine not found." -ForegroundColor Red
    Write-Host "Set env GODOT, or write the exe path into tools\godot_path.local (gitignored)."
    exit 2
}
Write-Host "engine: $engine"

if ($Import) {
    & $engine --headless --path $root --import
    Write-Host "import exit=$LASTEXITCODE"
}

$all = @("rules", "quality", "network", "seal", "netwindow", "roundloop", "nav", "py")
$list = if ($Only) {
    $Only -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} else {
    $all
}

$failed = 0
foreach ($n in $list) {
    if ($n -eq "py") {
        $env:PYTHONIOENCODING = "utf-8"
        & python tests\test_rules_v2.py
        if ($LASTEXITCODE -ne 0) { $failed++ }
        Write-Host "py exit=$LASTEXITCODE"
        continue
    }
    $gname = "run_${n}_check"
    & $engine --headless --path $root --script "res://tests/$gname.gd" > $null
    $code = $LASTEXITCODE
    if ($code -ne 0) { $failed++ }
    Write-Host "$gname exit=$code"
}

if ($failed -gt 0) {
    Write-Host "$failed check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "all checks passed"
