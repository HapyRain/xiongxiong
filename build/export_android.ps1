# 拍拍熊熊 · Android 导出脚本（PowerShell 7）
# 用法：
#   .\export_android.ps1              # debug APK
#   .\export_android.ps1 -Release     # release APK
#   .\export_android.ps1 -CheckOnly   # 只检查环境，不导出（缺项时 exit 1）
#   .\export_android.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
#
# 前置（缺一项都导不出）：
#   1) Godot 4.7.2 stable win64（必须带 console exe）
#   2) 导出模板 4.7.2：%APPDATA%\Godot\export_templates\4.7.2.stable\android_debug.apk
#   3) JDK 17（Godot 编辑器设置 export/android/java_sdk_path，不是 JAVA_HOME）
#   4) Android SDK（Godot 编辑器设置 export/android/android_sdk_path）：
#      platform-tools\adb.exe + build-tools\（28–36，4.7.2 默认 target 36）
#   5) debug keystore：%APPDATA%\Godot\keystores\debug.keystore（配好 JDK 后 Godot 会自动生成）

param(
    [switch]$Release,
    [switch]$CheckOnly,
    [string]$Godot = "",
    [string]$JavaSdk = "",
    [string]$AndroidSdk = ""
)

$ErrorActionPreference = 'Stop'

# 工程根 = 本脚本的上一级目录（不再写死旧机器路径）
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Templates   = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable"
$BuildOut    = Join-Path $ProjectRoot "build"
$ToolsRoot   = "E:\github\tools"

## JDK：参数 > JAVA_HOME > E:\github\tools\jdk-* > Adoptium 默认安装目录
function Find-Jdk([string]$Explicit) {
    $cands = @()
    if ($Explicit) { $cands += $Explicit }
    if ($env:JAVA_HOME) { $cands += $env:JAVA_HOME }
    if (Test-Path $ToolsRoot) {
        $cands += (Get-ChildItem $ToolsRoot -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName)
    }
    $cands += (Join-Path $env:LOCALAPPDATA "Programs\Eclipse Adoptium")
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c "bin\java.exe"))) { return (Resolve-Path $c).Path }
    }
    return $null
}

## Android SDK：参数 > ANDROID_HOME > ANDROID_SDK_ROOT > E:\github\tools\android-sdk > %LOCALAPPDATA%
function Find-AndroidSdk([string]$Explicit) {
    $cands = @()
    if ($Explicit) { $cands += $Explicit }
    if ($env:ANDROID_HOME) { $cands += $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT) { $cands += $env:ANDROID_SDK_ROOT }
    $cands += (Join-Path $ToolsRoot "android-sdk")
    $cands += (Join-Path $env:LOCALAPPDATA "Android\Sdk")
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c "platform-tools\adb.exe"))) { return (Resolve-Path $c).Path }
    }
    return $null
}

## 依次尝试：-Godot 参数 / $env:GODOT / PATH / 常见解压位置
function Find-GodotConsole([string]$Explicit) {
    $cands = @()
    if ($Explicit) { $cands += $Explicit }
    if ($env:GODOT) { $cands += $env:GODOT }
    $cmd = Get-Command "Godot_v4.7.2-stable_win64_console.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    $roots = @(
        (Join-Path $env:USERPROFILE "Desktop"),
        (Join-Path $env:USERPROFILE "Downloads"),
        "E:\github\tools",
        "C:\godot",
        "D:\godot"
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($r in $roots) {
        $hit = Get-ChildItem -Path $r -Filter "Godot*_console.exe" -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $cands += $hit.FullName }
    }
    foreach ($c in $cands) {
        if (-not $c) { continue }
        if (Test-Path $c -PathType Container) {
            $inner = Join-Path $c "Godot_v4.7.2-stable_win64_console.exe"
            if (Test-Path $inner) { return (Resolve-Path $inner).Path }
            continue
        }
        if ($c -like "*_console.exe") { return (Resolve-Path $c).Path }
        # 传进来的是主 exe（..._win64.exe）→ 找同目录 console
        $dir = Split-Path $c -Parent
        $sib = Join-Path $dir "Godot_v4.7.2-stable_win64_console.exe"
        if (Test-Path $sib) { return (Resolve-Path $sib).Path }
        return (Resolve-Path $c).Path
    }
    return $null
}

$miss = 0
function Test-Part($name, $ok, $hint) {
    if ($ok) { Write-Host "[OK]   $name" -ForegroundColor Green }
    else {
        Write-Host "[MISS] $name" -ForegroundColor Red
        Write-Host "       → $hint" -ForegroundColor Yellow
        $script:miss++
    }
}

Write-Host "==== 环境检查 ===="
Write-Host "工程根: $ProjectRoot"
$godotPath = Find-GodotConsole $Godot
$godotOk = [bool]$godotPath
Test-Part "Godot 4.7.2 console" $godotOk "解压 4.7.2 stable win64 后传 -Godot <..._console.exe>，或设 `$env:GODOT"
if ($godotOk) {
    Write-Host "       引擎: $godotPath"
    $ver = (& $godotPath --version 2>&1 | Out-String).Trim()
    Test-Part "Godot 版本 4.7.2" ($ver -like "4.7.2*") "当前: $ver"
}

$tplDebug   = Join-Path $Templates "android_debug.apk"
$tplRelease = Join-Path $Templates "android_release.apk"
Test-Part "导出模板 android_debug.apk"   (Test-Path $tplDebug)   "安装 Godot_v4.7.2-stable_export_templates.tpz → $Templates"
Test-Part "导出模板 android_release.apk" (Test-Path $tplRelease) "同上"

$javaHome = Find-Jdk $JavaSdk
$javaOk = [bool]$javaHome
if ($javaOk) { $env:JAVA_HOME = $javaHome }
Test-Part "JDK 17" $javaOk "解压 Temurin 17 到 E:\github\tools\jdk-*，或传 -JavaSdk <JDK 根目录>"

$sdk = Find-AndroidSdk $AndroidSdk
if ($sdk) { $env:ANDROID_HOME = $sdk }
$adbOk = $sdk -and (Test-Path (Join-Path $sdk "platform-tools\adb.exe"))
Test-Part "Android SDK platform-tools\adb" $adbOk "装 Android SDK（或 cmdline-tools 的 platform-tools），并在编辑器设置 export/android/android_sdk_path 指到 SDK 根"
$apksigner = $null
if ($sdk -and (Test-Path (Join-Path $sdk "build-tools"))) {
    $apksigner = Get-ChildItem (Join-Path $sdk "build-tools") -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
}
Test-Part "Android SDK build-tools\apksigner" ([bool]$apksigner) "sdkmanager `"build-tools;36.0.0`"（28–36 均可，4.7.2 默认 target 36）"

$ks = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
Test-Part "debug keystore" (Test-Path $ks) "配好 java_sdk_path 后 Godot 会自动生成；或跑 build\setup_android_env.ps1 生成"

$godotImported = Test-Path (Join-Path $ProjectRoot ".godot\global_script_class_cache.cfg")
Test-Part ".godot 首次导入缓存" $godotImported "先跑一次：& '$godotPath' --headless --path '$ProjectRoot' --import"

Write-Host ""
if ($miss -gt 0) {
    Write-Host "缺 $miss 项，先补齐再导出。" -ForegroundColor Red
} else {
    Write-Host "环境检查通过。" -ForegroundColor Green
}
if ($CheckOnly) {
    Write-Host ""
    Write-Host "（-CheckOnly：跳过导出）"
    if ($miss -gt 0) { exit 1 } else { exit 0 }
}
if (-not $godotOk) { Write-Host "Godot 缺失，终止。" -ForegroundColor Red; exit 1 }
if ($miss -gt 0) { Write-Host "环境不完整，终止。" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $BuildOut)) { New-Item -ItemType Directory -Force -Path $BuildOut | Out-Null }

# Godot 导出只读编辑器设置里的 Java/Android SDK 路径：每次导出前对齐一次（幂等）
$setup = Join-Path $PSScriptRoot "setup_android_env.ps1"
if ((Test-Path $setup) -and $javaOk -and $adbOk) {
    & $setup -JavaSdk $javaHome -AndroidSdk $sdk -Quiet
}

# 注意：headless 导出会以“编辑器实例”身份注册 MCP 注册表，退出时把运行中编辑器的条目删掉。
# 导出后若 MCP 工具报 no registry entry / AUTH_FAILED，重启 Godot 编辑器即可恢复。
$editors = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Godot' -and $_.ProcessName -notmatch 'console' }
if ($editors) {
    Write-Host "提示：检测到 Godot 编辑器在运行（PID $($editors.Id -join ',')）；本次 headless 导出可能清掉它的 MCP 注册，导出后 MCP 报错就重启编辑器。" -ForegroundColor Yellow
}
Set-Location $ProjectRoot
$outApk = if ($Release) { "build/xiongxiong-release.apk" } else { "build/xiongxiong-debug.apk" }
$mode   = if ($Release) { "--export" } else { "--export-debug" }

Write-Host ""
Write-Host "==== 开始导出：$mode Android → $outApk ===="
& $godotPath --headless $mode "Android" $outApk
$code = $LASTEXITCODE

$abs = Join-Path $ProjectRoot $outApk
if ($code -eq 0 -and (Test-Path $abs)) {
    $f = Get-Item $abs
    Write-Host ""
    Write-Host "导出成功" -ForegroundColor Green
    Write-Host "  路径: $($f.FullName)"
    Write-Host "  大小: $([math]::Round($f.Length/1MB,2)) MB"
    Write-Host "  包名: com.xiongxiong.demo"
    Write-Host ""
    Write-Host "安装：adb install -r `"$($f.FullName)`""
} else {
    Write-Host ""
    Write-Host "导出失败 (exit=$code)。常见缺口：" -ForegroundColor Red
    Write-Host "  - 导出模板未装到 $Templates"
    Write-Host "  - JDK / Android SDK 未填进 Godot 编辑器设置（export/android/*）"
    exit $code
}
