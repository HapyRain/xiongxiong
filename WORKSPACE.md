# 换工作区续作 · 环境与缺什么

给「换了台机器 / 另一个工作区 / 新会话」用：clone 仓库后照着补齐，再按 `SESSION-HANDOFF.md` 做需求。

---

## 仓库里有什么

| 内容 | 说明 |
|---|---|
| Godot 4.7 工程源码 | `project.godot`、`scripts/`、`scenes/`、`tests/` |
| 导出配置 | `export_presets.cfg`（竖版、包名） |
| 构建脚本 | `build/export_android.ps1`、`build/dl_font.py` |
| 规则镜像 | `tests/test_rules_v0.py` |
| 交接/规范 | `AGENTS.md`、`SESSION-HANDOFF.md`、本文件 |

**默认不推、可本地自己打的东西**：`build/xiongxiong-debug.apk`（约 70MB，GitHub 会警告；需要装机时用导出脚本现打）。

---

## 仓库外、换机后通常会缺的东西

这些**不在 git 里**，新环境要么重装，要么从旧机器拷：

| 依赖 | 本机参考路径 | 缺了会怎样 | 怎么补 |
|---|---|---|---|
| Godot **4.7.2** 控制台引擎 | `C:\Users\pc\XiaomiMiMoProjects\xiongxiong\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` | 跑不了 headless 回归 | 官网下 4.7.2 stable win64，路径改成你机器上的 |
| 导出模板 4.7.2 | `%APPDATA%\Godot\export_templates\4.7.2.stable` | 打不出 APK | 编辑器 → 管理导出模板 |
| JDK 17 | `JAVA_HOME=C:\Users\pc\AppData\Local\Programs\Eclipse Adoptium\jdk-17.0.20.8-hotspot\` | Android 导出失败 | 装 Temurin/OpenJDK 17，设 `JAVA_HOME` |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk`（本机 build-tools **36.0.0** + platform-tools） | 同上 | Android Studio 或 cmdline-tools；设 `ANDROID_HOME` |
| debug keystore | `%APPDATA%\Godot\keystores\debug.keystore` | 无法 debug 签名 | `export_android.ps1 -CheckOnly` 会提示；可从旧机器拷（**勿提交 git**） |
| **规则/设计文档镜像** | `C:\Users\pc\XiaomiMiProjects\xiongxiong\docs\`（**仓库外**） | 看不到冻结规则全文与架构稿 | 整目录拷贝，或按下方说明装回 |
| 字体资源 | 由 `build/dl_font.py` 等生成/下载 | 缺字体时 UI 不对 | 执行下载脚本 |

> **路径坑**：文档镜像在 `XiaomiMiProjects`（Mi），引擎在 `XiaomiMiMoProjects`（双 Mo）。**别搞混。** 本仓库内没有 `docs/`。

文档镜像至少应有：

```
docs/
  rules/minimal-rules-v0.md          ← 结算语义唯一冻结稿
  arch/peer-manager-multipath.md
  arch/network-session-fsm.md
  arch/quality-performance-tiers.md
  design/game-flow-v0.md
  testing/device-test-checklist.md
  android-export-build-notes.md
  SESSION-HANDOFF.md
```

---

## 可选工具

| 工具 | 用途 |
|---|---|
| `adb`（platform-tools） | 真机安装 `adb install -r build\xiongxiong-debug.apk` |
| Godot MCP（编辑器插件 + `.mcp.json`） | 改场景/UI；**须先在 Godot 编辑器打开本工程** |
| PowerShell 7 (`pwsh`) | 日常终端约定 |

---

## 首次打开检查清单

1. **改引擎路径**后跑回归（六个都要，`ALL PASS` / exit 0）：

```powershell
$g = "<你的 Godot 4.7.2 console.exe 全路径>"
foreach ($n in "run_rules_check","run_network_check","run_seal_check","run_quality_check","run_netwindow_check","run_nav_check") {
  & $g --headless --path <仓库路径> --script "res://tests/$n.gd" > $null
  "$n exit=$LASTEXITCODE"
}
```

2. 再跑规则镜像：`python tests/test_rules_v0.py`（改 `scripts/rules/resolve.gd` 必须同步该文件）。
3. 需要 APK 时：

```powershell
.\build\export_android.ps1 -CheckOnly   # 先看缺什么
.\build\export_android.ps1              # debug APK
```

4. 新增 `class_name` 后：`& $g --headless --path . --import`，否则报「标识符未声明」。

---

## 推送到 GitHub

本机直连 `github.com:443` 可能超时（DNS 常落到 `20.205.243.166`）。需本机代理（常见 `127.0.0.1:7897`）：

```powershell
$env:HTTPS_PROXY="http://127.0.0.1:7897"
$env:HTTP_PROXY="http://127.0.0.1:7897"
git push origin main
```

**提交约定**：不要把 `*.apk` / `*.keystore` 推上去；APK 本地 `export` 即可。

---

## 仍对不齐时

- headless 测不出布局/字体/聚光灯 → 用 F5 或真机看。
- 联机/搜房/节奏数字：以 `scripts/session/battle_tempo.gd` 与本仓库 `SESSION-HANDOFF.md` 为准；结算语义只认 `docs/rules/minimal-rules-v0.md`（镜像目录）。
- 文案：只用「我 / 对手」，规则出处写「致敬童年」。
