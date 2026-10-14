# 拍拍熊熊 · Android 导出脚本（PowerShell 7）
# 用法：
#   .\export_android.ps1              # debug APK
#   .\export_android.ps1 -Release     # release APK
#   .\export_android.ps1 -CheckOnly   # 只检查环境，不导出
#
# 前置：见 docs/android-export-build-notes.md

param(
    [switch]$Release,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = "D:\xiongxiong\xiongxiong"
$GodotDir    = "C:\Users\pc\XiaomiMiMoProjects\xiongxiong\Godot_v4.7.2-stable_win64.exe"
$Godot       = Join-Path $GodotDir "Godot_v4.7.2-stable_win64_console.exe"
$Templates   = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable"
$BuildOut    = Join-Path $ProjectRoot "build"

function Test-Part($name, $ok, $hint) {
    if ($ok) { Write-Host "[OK]   $name" -ForegroundColor Green }
    else     { Write-Host "[MISS] $name" -ForegroundColor Red; Write-Host "       → $hint" -ForegroundColor Yellow }
}

Write-Host "==== 环境检查 ===="
$godotOk = Test-Path $Godot
Test-Part "Godot 4.7.2 console" $godotOk "确认 $Godot"

$ver = ""
if ($godotOk) {
    $ver = (& $Godot --version 2>&1 | Out-String).Trim()
    Test-Part "Godot 版本" ($ver -like "4.7.2*") "当前: $ver"
}

$tplDebug   = Join-Path $Templates "android_debug.apk"
$tplRelease = Join-Path $Templates "android_release.apk"
Test-Part "导出模板 android_debug.apk"   (Test-Path $tplDebug)   "安装 Godot_v4.7.2-stable_export_templates.tpz → $Templates"
Test-Part "导出模板 android_release.apk" (Test-Path $tplRelease) "同上"

$java = Get-Command java -ErrorAction SilentlyContinue
$javaHome = $env:JAVA_HOME
$javaOk = [bool]($java) -or ($javaHome -and (Test-Path (Join-Path $javaHome "bin\java.exe")))
Test-Part "JDK (java / JAVA_HOME)" $javaOk "安装 JDK 17 并设置 JAVA_HOME；Editor Settings → export/android/java_sdk_path"

$sdk = $env:ANDROID_HOME; if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$adbOk = $sdk -and (Test-Path (Join-Path $sdk "platform-tools\adb.exe"))
Test-Part "Android SDK platform-tools\adb" $adbOk "安装 Android Studio 或 cmdline-tools；设 ANDROID_HOME"
$apksigner = $null
if ($sdk -and (Test-Path (Join-Path $sdk "build-tools"))) {
    $apksigner = Get-ChildItem (Join-Path $sdk "build-tools") -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
}
Test-Part "Android SDK build-tools\apksigner" ([bool]$apksigner) "安装 build-tools 34.x"

$ks = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
Test-Part "debug keystore" (Test-Path $ks) "keytool -genkeypair ... 见 device-test-checklist.md §2"

if ($CheckOnly) {
    Write-Host ""
    Write-Host "（-CheckOnly：跳过导出）"
    exit 0
}

if (-not $godotOk) { Write-Host "Godot 缺失，终止。" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $BuildOut)) { New-Item -ItemType Directory -Force -Path $BuildOut | Out-Null }

Set-Location $ProjectRoot
$outApk = if ($Release) { "build/xiongxiong-release.apk" } else { "build/xiongxiong-debug.apk" }
$mode   = if ($Release) { "--export" } else { "--export-debug" }

Write-Host ""
Write-Host "==== 开始导出：$mode Android → $outApk ===="
& $Godot --headless $mode "Android" $outApk
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
    Write-Host "  - JDK / ANDROID_HOME 未配置"
    Write-Host "  详见 docs/android-export-build-notes.md"
    exit $code
}
