# AGENTS.md · 拍拍熊熊（xiongxiong）

Godot 4.7 移动端 1v1 回合对战 Demo（攒/波/防），GDScript，未上架。
**这不是 Node/JS 工程：没有 `package.json`、没有 lint/format/typecheck、没有 `npm test`。** `.mcp.json` 只是 Godot MCP 桥接配置，别据此推断技术栈。

## 项目定位（阶段，2026-10-17 确认）

- 这是**完整度较高的 MVP 基线**：玩法闭环（攒/波/防 + 2 拍 + 单机/联机 + 断线处理）已跑通，用户已真机试玩，无阻塞体验的 bug。
- **前端/视觉/页面结构后续会重做**：当前 UI 只求可用、可读、能走完流程，不追加视觉打磨，不为表现层加复杂度。
- 判断标准：**结算语义、房主权威、竖版契约是长期资产，必须严谨**；UI 布局、文案包装、特效是消耗品，随前端重做一起换。
- 下一阶段：在这套基线上**加功能、加模块、加具体功能页面**。新功能优先「最短路径跑通 + 一条 headless 断言」，不做框架化抽象。

## 关键路径（别猜错）

| 用途 | 路径 |
|---|---|
| Godot 工程（唯一） | **仓库根目录**（命令里一律 `--path .`，不写绝对路径） |
| Godot 4.7.2 console 引擎 | 优先 `$env:GODOT`；否则由 `tools/run_checks.ps1` 自动探测（各机路径见 `docs/ENVIRONMENT.md`） |
| 文档 / 规则冻结稿 | 仓库内 `docs/rules/game-rules-v2.md`（已随 v2 提交入库） |

- **受版本控制的文档（AGENTS / WORKSPACE / SESSION-HANDOFF 等）禁止写机器绝对路径**：换机一拉就错。机器差异只写 `docs/ENVIRONMENT.md`（已 ignore，每台机各留一份）。
- 引擎路径一律走 `$env:GODOT` 或 `.\tools\run_checks.ps1` 自动探测；其它脚本用 `-Godot` / `$env:GODOT` 覆盖，不写死。
- **本机环境细节（引擎/JDK/SDK/导出脚本/MCP 接入与验证方式）：`docs/ENVIRONMENT.md`**。该文件在 `.gitignore` 里，只作本机交接，**不要提交/推送**。
- 规则权威：**`docs/rules/game-rules-v2.md`（已定稿，唯一实现依据；`minimal-rules-v0.md` 是历史）**。本机可执行的权威是 **`scripts/rules/*` 与 `tests/test_rules_v2.py` 双镜像**，两者必须一致。

## 验证命令（改完必跑）

测试是 **Godot headless SceneTree 脚本**，`ALL PASS` + exit 0 = 通过：

```powershell
# 推荐：一条命令跑完全部（自动探测引擎，两机通用；首次先做一次 --import，见「硬约束 6」）
.\tools\run_checks.ps1
# 只跑部分：.\tools\run_checks.ps1 -Only ui,nav
```

**8 个自检，全部都要跑**（都继承 `SceneTree`、单进程，不需要真实窗口/导出模板）：

`run_rules_check` · `run_network_check` · `run_seal_check` · `run_quality_check` · `run_netwindow_check` · `run_roundloop_check` · `run_nav_check` · `run_ui_check`

另有一个 Python 规则镜像测试：`python tests/test_rules_v2.py`（Python 3.8 可跑，155 条；控制台 cp936 中文乱码时设 `$env:PYTHONIOENCODING='utf-8'`）。

**当前基线：8/8 全绿，断言合计 784 条**（2026-10-27，全量 review 修复批次后：网络身份/重放闸/双镜像对称/UI 信号卫生 + 初版全功能）。v2 回归：对撞矩阵每一类、CD/封盾/劝降、双镜像 155 条、每小局判分/12 分终场/平局保底/快照防篡改。
**断言数量不是验收标准，"能失败"才是**：加/改断言时先问一句「把对应实现删掉，它会不会红」。删掉 `_check_winner` 或把心跳窗口退回 1× 间隔，`run_rules_check` / `run_seal_check` 必须变红。

建议顺序：先 `run_rules_check`（最快，纯逻辑）→ 按改动范围挑对应的 → 最后 `run_nav_check`（最重，会起双端联机+人机接管）。
`run_quality_check` 会写 `user://settings.cfg`（画质偏好会被改成测试值），跑完可回设置面板改回。

## 硬约束

1. **`scripts/rules/*` 结算语义禁止口头改。** 改规则必须先变更记录走冻结流程。
2. **`tests/test_rules_v2.py` 是 `scripts/rules/resolve.gd` 的逐行镜像**（不是包装调用）。改了 resolve 必须同步改这个 Python 文件，否则两套结算表会静默分叉。
3. **房主权威**：`PeerManager`（autoload `Net`）里客户端只 apply 房主下发的结算，**绝不本地调 `GameResolve`**。
4. **竖版是契约**：`project.godot` 的 390×820 / `orientation=1` 与 `export_presets.cfg` 的 `screen/orientation=1` 必须同时成立，`run_nav_check` 会静态校验这两处。
5. **headless 下 `static func` 不能直接写 autoload 名**（如 `Net`），编译期解析不到。要像 `scripts/ui/ui_nav.gd` 那样运行时取：`Engine.get_main_loop().root.get_node_or_null("Net")`。
6. **新增 `class_name` 后必须重建 class cache**：`& $g --headless --path . --import`，否则其它脚本报"标识符未声明"。`.godot/global_script_class_cache.cfg` 即该索引（`.godot/` 已被 `.gitignore` 忽略）。
7. **提交只管锁定，结算等拍2**：`submit_action()` 在 3000d5e 之后只写入 `_locks`/`_pending_actions`，真正揭示必须调 `reveal_phase()`（或走 `request_timeout_default()`）。headless 测试里提交完要手动 `reveal_phase()` + `_pump()` 才会结算（`run_nav_check.gd` 已按此写法，`run_roundloop_check.gd` 用控制器驱动）。
8. 脚本旁的 `*.gd.uid` 已入库，勿删勿手改。
9. 文案规范：角色只用**「我 / 对手」**，禁用颜色昵称；规则出处不可考，统一写**「致敬童年」**，不写「完整还原」。

## 架构边界

- `scripts/rules/` — `GameRules` / `BattleState` / `GameResolve`，**纯逻辑，禁止耦合 UI、画质、网络**。判分/终场/兜底出招的唯一口径也在 `BattleState`（`settle_round_after_resolve` / `is_match_over` / `match_winner` / `reset_round_keep_score` / `default_action`），会话层只调用不重写。
- `scripts/network/` — `NetworkProvider` 抽象 + `LocalProvider`（测试/热座）/ `EnetProvider`（真联机）/ `WebSocketProvider`（抖音预留桩）。
- `scripts/session/` — `PeerManager`(autoload `Net`)、`BattleController`（单机）、`NetworkedBattleController`、`NetworkSessionFSM`（断线封存 7 态）、`AiOpponent`。
- `scripts/performance/` — `QualitySettings`(autoload) + `FpsGuard`，**只动表现层**（帧率/特效/降采样），不读写 rules 与对局状态。
- `scripts/ui/` — `menu` / `main`(单机) / `net_battle_ui` / `settings_panel` / `ui_nav`(导航) / `ui_theme` / `battle_fx`。
- `scenes/` — `menu.tscn` 是 `run/main_scene`，入口从这里开始。
- `build/` **部分是源码**：`export_android.ps1`、`dl_font.py`、`fix_spot.py` 在里面；但 `xiongxiong-debug.apk`（约 73MB）仍被 git 跟踪，改动会刷出巨大的 diff，提交前留意（要停跟踪需单独决策，别顺手做）。

## 网络（局域网）

- **传输 = ENet over UDP**（`scripts/network/enet_provider.gd`，`ENetConnection` + `put_packet` 可靠通道）；消息是自定义 Dictionary 信封 `{v,type,round,from_role,payload}`，**不用** Godot RPC / MultiplayerSynchronizer。
- 端口：游戏 `47001`，房间发现 `47000`（UDP 广播）。`WebSocketProvider` 是**空桩**（抖音/远程对局预留，所有方法 `ERR_UNAVAILABLE`）——跨网对战要走那条路，别在 ENet 上硬加。
- 心跳/质量判定在 `PeerManager._pump_session()` + `NetworkSessionFSM`：1s 一次心跳；**丢包窗口 = 2.5×间隔**（2.5s 静默算 1 次 miss，2 次≈3.5s 提示、5 次≈6.5s 封存）；延迟/抖动要**连续 2 次**采样超标才降级。改阈值前先看 `run_seal_check` 的「健康链路不误报」回归。
- **房主权威**：只接受唯一对端（客户端认房主 1，房主由 hello 学习）的数据包；房主不采纳客户端发来的胜负/恢复快照/倒计时/链路恢复。
- 已知未实现：**ENet 自动重连**。断线当前是「先封存（快照保留）→ 转人机接管」；真正的「重连→双方同意→3s 倒计时→恢复」只差传输层重连握手，FSM 那套已经写好。

## Android 导出

```powershell
.\build\setup_android_env.ps1                        # 一键把 JDK/SDK 路径写进 Godot 编辑器设置（先关编辑器）
.\build\export_android.ps1 -CheckOnly   # 只查环境，不导出（缺项时 exit 1）
.\build\export_android.ps1              # debug APK
.\build\export_android.ps1 -Release     # release APK
.\build\export_android.ps1 -Godot "C:\path\Godot_v4.7.2-stable_win64_console.exe"
```

**导出链已装好（各机具体路径见 `docs/ENVIRONMENT.md`）**：JDK 17、Android SDK（platform-tools + build-tools 36.0.0 + platforms android-36）、导出模板 `%APPDATA%\Godot\export_templates\4.7.2.stable`、debug keystore。`export_android.ps1` 会自动探测，不依赖 `JAVA_HOME`/`ANDROID_HOME`，并在导出前调用 `setup_android_env.ps1` 对齐编辑器设置。

包名 `com.xiongxiong.demo`，产物 `build/xiongxiong-debug.apk`。`-CheckOnly` 会逐项报缺。

前置依赖（**前 4 项是硬门槛**，Godot 4.7.2 导出只认编辑器设置，`JAVA_HOME`/`ANDROID_HOME` 不够）：

1. Godot 4.7.2 stable win64（含 console exe）
2. 导出模板 4.7.2 → `%APPDATA%\Godot\export_templates\4.7.2.stable\android_debug.apk`
3. JDK 17 → 编辑器设置 `export/android/java_sdk_path`
4. Android SDK（platform-tools + build-tools **28–36，建议 36.0.0**；4.7.2 默认 target SDK 36）→ 编辑器设置 `export/android/android_sdk_path`
5. debug keystore → `%APPDATA%\Godot\keystores\debug.keystore`（配好 JDK 后 Godot 自动生成）
6. 首次导入：`.\tools\run_checks.ps1 -Import`（或 `& $g --headless --path . --import`）

不需要 NDK / CMake / gradle（`use_gradle_build=false`，用官方预构建模板）。安装：`adb install -r build\xiongxiong-debug.apk`（adb 路径见 `docs/ENVIRONMENT.md`）。

## Godot MCP（重要）

`addons/godot_mcp_toolkit` 是**编辑器内插件**，`.mcp.json` 里的 npm 桥（`npx -y @npgamedev/godot-mcp-server`，要求 node ≥ 22）只跟**编辑器里当前打开的工程**通信。
- **MCP 开着时优先用它做 Godot 开发**：场景/节点增删改（`scene_create_node`/`node_set_property`/`control_set_layout`）、截图（`editor_screenshot`/`runtime_screenshot`）、运行时状态检查（`runtime_get_node_state`）都比手写 `.tscn` 可靠；脚本内容大改仍走文本工具。
- **导出 APK 会停掉 MCP server**：`build\export_android.ps1` 结束后 MCP 断连（`[MCPServer] stopped`）。顺序建议：先做完 MCP 相关操作 → 再导出；导出后需要 MCP 就**重启 Godot 编辑器**（重新打开本工程）。要让它作用到本仓库，**必须先在 Godot 编辑器里打开本仓库根目录**，否则工具会连到别的工程实例上（甚至另一个 MCP runtime 端口 6570–6585）。改场景/UI/脚本优先走 MCP，而不是手写 `.tscn`。

## 工作约定

- 终端**完全使用 PowerShell 7 (pwsh)**，不用 Windows PowerShell 5.1：执行命令一律显式走 `pwsh -NoProfile`（agent 默认 shell 是 PS 5.1，不得依赖）；跑自检时直接调引擎并读 `$LASTEXITCODE`（需要退出码时才这样，一般交互式启动用 `Start-Process`）。
- 推送走本机代理：`$env:HTTPS_PROXY="http://127.0.0.1:7897"`。**github.com 直连不稳（时通时断）**，`git fetch/push` 失败先挂代理再试；下载大文件可改用镜像（`https://gh-proxy.com/https://github.com/...` 实测可用）。
- **走代理时 git 必须加 `-c http.sslBackend=openssl`**：默认 schannel 在 CONNECT 隧道里 TLS 握手必失败（`schannel: failed to receive handshake`）。完整可用命令：`git -c http.sslBackend=openssl -c http.proxy=http://127.0.0.1:7897 -c https.proxy=http://127.0.0.1:7897 pull --ff-only origin main`。
- **拉代码用 fast-forward merge**：本地 APK 常有未提交改动，git pull（rebase）会直接报错 → 用 git merge --ff-only origin/main（不覆盖本地改动），或先 git stash。
- 大改动先拆 subagent；派单时写清工程路径、禁止改 `scripts/rules/*`、验收命令。
- **提交用显式路径**（`git add -- <文件>`），不要 `git add -A`：`build/xiongxiong-debug.apk` 是 73MB 跟踪文件、`docs/ENVIRONMENT.md` 已 ignore、环境修复批次可能还没提交。
- DSH 沙箱默认禁止写 `.git/`：`git add/commit` 报 `Unable to create '.git/index.lock': Permission denied` 时，用一次性 `danger-full-access` 提权执行同一条命令，或请用户在外部终端提交。

## 当前状态（2026-10-27）

- **v2 规则已落地**：`scripts/rules/*` 按 `docs/rules/game-rules-v2.md` 重写（血4/盾3/气10、12 分制、11 技能 + 劝降、对撞矩阵、六步结算管线）；判分/终场/兜底出招在 `BattleState`，按分解锁、12 分终场、**平局保底（第 3 次起各 +1，防无限拖）**；双镜像 `scripts/rules/*` ↔ `tests/test_rules_v2.py`（155 条）；**8 个自检 784 条断言全绿**。
- **UI 已有 v2 §8 技能条**：13 技能格 + CD/解锁角标 + 顶部分数条（单机/联机都有）；视觉仍是一次性实现，随前端重做再换。
- 本轮**初版全功能**：经典/课间双模式（规则预设）、单人难度、技能精通、联机房间/搜索/准备/5s 倒计时/离开回落、12 屏占位 UI、返回路由与二次确认、第 8 个 UI 冒烟自检。桌面/真机视觉仍是占位（`【占位】`），下一阶段做前端重做。
- `main` 头部 **`2190e2f`**：初版全功能（`6f4edd9`）+ MCP 使用顺序文档。**未提交：2026-10-27 全量 review 修复批次**（多角度审查后修 3 Critical + 全部 Important/Minor：ENet 身份劫持/陌生对端 DoS、重放闸补全、双镜像 ㉖ 对称、restore 防篡改、模式外动作消毒、lobby 守卫三件套、UI 信号卫生/返回键清理等，29 文件）——本机复跑 8 自检（784 断言）+ Python 镜像（155 条）全绿。
- 工作区未提交项：review 修复批次（见上）、`build/xiongxiong-debug.apk`（73MB 跟踪文件，重新导出后常驻改动）与 `build/gh_proxy.py`、`build/git_push_via_proxy.py`、`build/start_gh_proxy.bat`（未跟踪的代理辅助脚本）。是否提交、APK 是否停跟踪由用户决定。
- 本机已装引擎 + `.godot` 已导入；Android 导出链已装好，`build\xiongxiong-debug.apk` 已用本机 debug key 打出（v2+v3 签名，包名 `com.xiongxiong.demo`）。
- 用户已真机试玩联机流程，**体感无阻塞 bug**；真机当前仍未连接。
- 换机器后：按 `WORKSPACE.md` 补引擎/模板/JDK/SDK，再跑 `build\setup_android_env.ps1`；脚本里所有路径都已不再写死旧机。

## 交接文档

`SESSION-HANDOFF.md`（根目录）记录待办优先级与「节奏约定」。其回归清单与上方「验证命令」一致（**8 个**，统一跑 `.\tools\run_checks.ps1`），两边任一改动都要同步。
