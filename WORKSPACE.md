# 换工作区续作 · 环境与缺什么

给「换了台机器 / 另一个工作区 / 新会话」用：clone 仓库后照着补齐，再按 `SESSION-HANDOFF.md` 做需求。

> 代码状态（2026-10-27）：v2 规则已落地（`docs/rules/game-rules-v2.md`：12 分制/11 技能/对撞矩阵，双镜像 `tests/test_rules_v2.py`）；**8 个 headless 自检全绿（784 断言）**、Android 导出链已就绪并打出 APK（v2+v3 签名）。
> **本机具体路径一律记在 `docs/ENVIRONMENT.md`**（已 ignore，每台机各留一份）；受版本控制的文档不写机器绝对路径。工作区未提交项见 AGENTS「当前状态」。

---

## 仓库里有什么

| 内容 | 说明 |
|---|---|
| Godot 4.7 工程源码 | `project.godot`、`scripts/`、`scenes/` |
| 测试 | `tests/` 下 **8 个** `run_*_check.gd`（当前 784 条断言）+ `tests/test_rules_v2.py`（规则镜像，155 条） |
| 导出配置 | `export_presets.cfg`（竖版、包名） |
| 构建脚本 | `build/export_android.ps1`、`build/dl_font.py`、`build/fix_spot.py`、`tests/gen_sfx.py`（路径均按脚本位置推导，可移植） |
| 资源 | 已含 Noto CJK 字体（16MB）与 5 个 wav，**无需重新下载** |
| 交接/规范 | `AGENTS.md`、`SESSION-HANDOFF.md`、本文件 |

**APK 现状**：`build/xiongxiong-debug.apk`（73,116,250 B）**仍被 git 跟踪**，历史里还有 3 个版本，`.git` 已 138MB。`.gitignore` 没写 `*.apk`，加 ignore 也不会停跟踪——要不要 `git rm --cached` 是单独决策，别顺手做；改 APK 会刷出巨大 diff，提交前留意。

---

## 仓库外、换机后通常会缺的东西

| 依赖 | 本机现状 | 缺了会怎样 | 怎么补 |
|---|---|---|---|
| Godot **4.7.2** 控制台引擎 | ✅ 已装（路径见 `docs/ENVIRONMENT.md`；解压目录名带 `.exe`，里面主 exe + console exe 平铺） | 跑不了 headless 回归 | 官网/GitHub releases 下 4.7.2 stable win64 zip（82MB）；`tools/run_checks.ps1` 自动探测，路径特殊就写 `tools/godot_path.local` 或设 `$env:GODOT` |
| 导出模板 4.7.2 | ✅ 已装 `%APPDATA%\Godot\export_templates\4.7.2.stable\`（android_debug/release.apk 都在） | 打不出 APK | 源包 `Godot_v4.7.2-stable_export_templates.tpz`（1.22GB）解压后把 `templates/*` 放进去 |
| JDK 17 | ✅ 已装（路径见 `docs/ENVIRONMENT.md`，Temurin 17.x） | Android 导出失败 | 已写入编辑器设置 `export/android/java_sdk_path`（JAVA_HOME 只是给命令行用） |
| Android SDK | ✅ 已装（路径见 `docs/ENVIRONMENT.md`；platform-tools + build-tools 36.0.0 + platforms android-36） | 同上 | 已写入编辑器设置 `export/android/android_sdk_path`；包管理用 `android.exe --sdk=... sdk install <pkg>`（新版 CLI 取代 sdkmanager） |
| debug keystore | ✅ 已生成 `%APPDATA%\Godot\keystores\debug.keystore`（alias `androiddebugkey`） | 无法 debug 签名 | 删了重跑 `build\setup_android_env.ps1` 会重建 |
| adb | ✅ SDK platform-tools 自带（个别模拟器另带一份，路径见 `docs/ENVIRONMENT.md`） | 装不了机 | 插手机后 `adb devices -l` |
| **文档镜像 `docs/`** | 旧机的过程文件未随仓库迁移，本机没有 | 看不到早期架构稿 | 不阻塞开发；规则权威 = `docs/rules/game-rules-v2.md`，可执行权威 = `scripts/rules/*` + `tests/test_rules_v2.py` 双镜像 |
| 字体资源 | ✅ 已在仓库（`assets/fonts/NotoSansSC-Regular.otf`） | — | 不必跑 `dl_font.py` |

> 旧机交接文档里出现的机器路径（用户目录、仓库盘符、工具目录）在本机都不存在，一律按 `docs/ENVIRONMENT.md` 换算。

---

## 首次打开检查清单

1. 首次导入（不跑会「标识符未声明」，7 个自检全挂）：

```powershell
.\tools\run_checks.ps1 -Import   # 内含 --import，10–60s，中断就删 .godot 重来
```

2. 跑 8 个自检（`ALL PASS` / exit 0 才算过）：

```powershell
.\tools\run_checks.ps1          # 自动探测引擎，跑完 8 自检 + Python 镜像
# 或手动：$g = $env:GODOT（引擎路径），工程一律 --path .
```

3. 规则镜像：`$env:PYTHONIOENCODING='utf-8'; python tests/test_rules_v2.py`（155 条 `ALL PASS` / exit 0）。
4. 打 APK（环境已就绪，直接跑）：

```powershell
.\build\export_android.ps1 -CheckOnly   # 体检，应全 OK
.\build\export_android.ps1              # debug APK → build\xiongxiong-debug.apk（约 70MB，v2+v3 签名）
.\build\export_android.ps1 -Release     # release APK
adb install -r build\xiongxiong-debug.apk
```

5. 换机 / 重装后：装引擎 → 解压模板到 `%APPDATA%\Godot\export_templates\4.7.2.stable` → 解压 JDK/SDK（自选目录，路径记入 `docs/ENVIRONMENT.md`）→ 跑 `.\build\setup_android_env.ps1`。
   **先关掉 Godot 编辑器再跑**，否则编辑器退出时会把自己的旧设置写回文件；脚本会提示 `exit=2`。
6. 需要 APK 时：`.\build\export_android.ps1 -CheckOnly`（缺项 exit 1）→ 按上面表格补齐 → `.\build\export_android.ps1`。

---

## 日常开发循环

1. 改代码（`scripts/`、`scenes/`；结算语义在 `scripts/rules/*`，别口头改）。
2. 跑回归：`.\tools\run_checks.ps1`（全部 `ALL PASS` / exit 0，当前 784 条断言）。
3. 改过 `resolve.gd` 就同步 `tests/test_rules_v2.py` 并跑一遍。
4. 新增 `class_name` 后：`.\tools\run_checks.ps1 -Import`（重建 class cache），否则报「标识符未声明」。
5. F5 真窗口 / 真机看布局、字体、特效（headless 测不出来）。
6. 要装机就 `.\build\export_android.ps1` → `adb install -r build\xiongxiong-debug.apk`。

> **MCP 小坑**：用 `export_android.ps1` 打 APK 时（headless 编辑器实例）会覆盖 MCP 注册表，运行中的 Godot 编辑器会“掉线”——之后 MCP 工具报 `no registry entry / AUTH_FAILED` 时，**重启 Godot 编辑器**即可恢复。
>
> 装好的安装包可删掉省空间（约 1.4GB）：下载的 `Godot_v4.7.2-stable_export_templates.tpz`、`OpenJDK17U-*.zip` 等压缩包；已解压的 `jdk-17*` / `android-sdk` 不能删。

> **git 小坑**：DSH 沙箱默认禁止写 `.git/`，`git add/commit` 会报 `Unable to create '.git/index.lock': Permission denied`。用一次性 `danger-full-access` 提权跑同一条命令，或请用户在外部终端提交。

---

## 推送到 GitHub

- 远端：`https://github.com/HapyRain/xiongxiong`（私有库）。
- 本机 `github.com:443` **直连不稳（时通时断）**，推送前先挂本机代理（默认 `127.0.0.1:7897`，代理进程见 `docs/ENVIRONMENT.md`）：

```powershell
git -c http.sslBackend=openssl -c http.proxy=http://127.0.0.1:7897 -c https.proxy=http://127.0.0.1:7897 push origin main
```

- **走代理必须加 `-c http.sslBackend=openssl`**：默认 schannel 在 CONNECT 隧道里 TLS 握手必失败（`schannel: failed to receive handshake` / `SSL_ERROR_SYSCALL`）；先确认代理在跑。**不要**用 `http.sslVerify=false` 绕过校验。
- 下载大文件（引擎/模板）直连 GitHub 不稳时用镜像：`https://gh-proxy.com/https://github.com/<org>/<repo>/releases/download/...`（实测 200）。

---

## 仍对不齐时

- headless 测不出布局/字体/聚光灯/真机观感 → 用 F5 或真机看。
- 联机/搜房/节奏数字：以 `scripts/session/battle_tempo.gd` 与本仓库 `SESSION-HANDOFF.md` 为准。
- 结算语义只认 `scripts/rules/*` 与 `tests/test_rules_v2.py` 双镜像（权威文档 `docs/rules/game-rules-v2.md`）。
- 文案：只用「我 / 对手」，规则出处写「致敬童年」。
