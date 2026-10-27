# 拍拍熊熊 · Android 开发环境一键配置（PowerShell 7）
#
# 作用（幂等，可反复跑）：
#   1) 把 JDK / Android SDK 路径写进 Godot **编辑器设置**（导出只认这里，不认 JAVA_HOME/ANDROID_HOME）
#   2) 缺 debug keystore 时用 keytool 生成
#   3) 把 JAVA_HOME / ANDROID_HOME 写入「用户环境变量」，方便 adb / sdkmanager
#
# 用法：
#   .\setup_android_env.ps1
#   .\setup_android_env.ps1 -JavaSdk "C:\path\to\jdk-17" -AndroidSdk "C:\path\to\Android\Sdk"
#   .\setup_android_env.ps1 -Quiet
#
# 注意：**先关掉 Godot 编辑器再跑**。编辑器开着时它退出会把自己的内存设置写回文件，覆盖这里写的路径。
#       （关掉后跑一次本脚本，再打开编辑器即可。）

param(
    [string]$JavaSdk = "",
    [string]$AndroidSdk = "",
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Find-Jdk([string]$Explicit) {
    $cands = @()
    if ($Explicit) { $cands += $Explicit }
    if ($env:JAVA_HOME) { $cands += $env:JAVA_HOME }
    $cands += (Join-Path $env:LOCALAPPDATA "Programs\Eclipse Adoptium")
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c "bin\java.exe"))) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Find-AndroidSdk([string]$Explicit) {
    $cands = @()
    if ($Explicit) { $cands += $Explicit }
    if ($env:ANDROID_HOME) { $cands += $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT) { $cands += $env:ANDROID_SDK_ROOT }
    $cands += (Join-Path $env:LOCALAPPDATA "Android\Sdk")
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c "platform-tools\adb.exe"))) { return (Resolve-Path $c).Path }
    }
    return $null
}

$javaHome = Find-Jdk $JavaSdk
$sdk      = Find-AndroidSdk $AndroidSdk
if (-not $javaHome) { throw "找不到 JDK 17：传 -JavaSdk <JDK 根目录>，或解压 Temurin 17 到 %LOCALAPPDATA%\Programs\Eclipse Adoptium" }
if (-not $sdk)      { throw "找不到 Android SDK：传 -AndroidSdk <SDK 根目录>，或安装到 %LOCALAPPDATA%\Android\Sdk" }

$apksigner = Get-ChildItem (Join-Path $sdk "build-tools") -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue |
             Sort-Object FullName -Descending | Select-Object -First 1
if (-not $apksigner) { throw "SDK 里没有 build-tools\*\apksigner.bat，先跑：android.exe --sdk=$sdk sdk install `"build-tools;36.0.0`"" }

# ---- 1) debug keystore ----
$ks = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
$ksCreated = $false
if (-not (Test-Path $ks)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $ks) | Out-Null
    & (Join-Path $javaHome "bin\keytool.exe") -genkeypair -v -keystore $ks `
        -alias androiddebugkey -storepass android -keypass android `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Android Debug,O=Android,C=US" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ks)) { throw "keytool 生成 debug.keystore 失败 (exit=$LASTEXITCODE)" }
    $ksCreated = $true
}

# ---- 2) Godot 编辑器设置 ----
$es = Get-ChildItem (Join-Path $env:APPDATA "Godot") -Filter "editor_settings-*.tres" -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $es) { throw "没有 editor_settings-*.tres：先启动一次 Godot 编辑器（打开本工程）再跑本脚本" }

$javaVal = $javaHome.Replace('\', '/')
$sdkVal  = $sdk.Replace('\', '/')
$text = [IO.File]::ReadAllText($es.FullName)
$text = $text -replace '(?m)^export/android/(java_sdk_path|android_sdk_path) = .*\r?\n', ''
if (-not $text.EndsWith("`n")) { $text += "`n" }
$text += "export/android/java_sdk_path = `"$javaVal`"`nexport/android/android_sdk_path = `"$sdkVal`"`n"
Copy-Item $es.FullName "$($es.FullName).bak" -Force
[IO.File]::WriteAllText($es.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))

# ---- 3) 用户环境变量（新开终端生效）----
[Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "User")
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdk, "User")
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdk

# ---- 汇总 ----
$godotRunning = [bool](Get-Process | Where-Object { $_.ProcessName -match '^Godot' })
if (-not $Quiet) {
    Write-Host "==== Android 开发环境 ====" -ForegroundColor Cyan
    Write-Host "JDK          : $javaHome"
    Write-Host "Android SDK  : $sdk"
    Write-Host "build-tools  : $($apksigner.Directory.FullName)"
    Write-Host "keystore     : $ks $(if ($ksCreated) { '(新建)' } else { '(已存在)' })"
    Write-Host "编辑器设置   : $($es.FullName)"
    Write-Host "   export/android/java_sdk_path    = $javaVal"
    Write-Host "   export/android/android_sdk_path = $sdkVal"
    Write-Host "环境变量     : JAVA_HOME / ANDROID_HOME 已写入用户变量（新终端生效）"
    if ($godotRunning) {
        Write-Host ""
        Write-Host "⚠ Godot 编辑器正在运行：请关闭后重跑本脚本，否则关闭时可能把设置写回旧值。" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "下一步：.\build\export_android.ps1 -CheckOnly" -ForegroundColor Green
}

if ($godotRunning) { exit 2 } else { exit 0 }
