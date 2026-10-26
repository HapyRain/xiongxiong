# Run all headless checks + python mirror. Engine auto-detected; override with $env:GODOT.
# Usage: .\tools\run_checks.ps1 [-Only rules,quality,...] [-Import]
param(
    # string[]：`-Only rules,py` 不写引号时 PowerShell 绑成数组，这里统一再按逗号拆
    [string[]]$Only = @(),
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

$all = @("rules", "quality", "network", "seal", "netwindow", "roundloop", "nav", "ui", "py")
$list = if ($Only.Count -gt 0) {
    $Only | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} else {
    $all
}

$failed = 0
foreach ($n in $list) {
    if ($n -eq "py") {
        $env:PYTHONIOENCODING = "utf-8"
        $gname = "py"
        $lines = @(& python tests\test_rules_v2.py 2>&1 | ForEach-Object { "$_" })
    } else {
        $gname = "run_${n}_check"
        $lines = @(& $engine --headless --path $root --script "res://tests/$gname.gd" 2>&1 | ForEach-Object { "$_" })
    }
    $code = $LASTEXITCODE
    # 只看 exit code 会假绿：push_error 不改退出码，必须扫输出。
    # 排除退出时 "resources still in use at exit" 这类已知噪音。
    $errs = @($lines | Where-Object {
        ($_ -match "(USER )?(SCRIPT )?ERROR") -and
        $_ -notmatch "resources still in use at exit"
    })
    if ($code -ne 0 -or $errs.Count -gt 0) { $failed++ }
    Write-Host "$gname exit=$code"
    if ($errs.Count -gt 0) {
        Write-Host "  $($errs.Count) error line(s), first: $($errs[0])" -ForegroundColor Red
    }
}

if ($failed -gt 0) {
    Write-Host "$failed check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "all checks passed"
