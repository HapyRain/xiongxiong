# AGENTS.md · 拍拍熊熊（xiongxiong）

Godot 4.7 移动端 1v1 回合对战 Demo（攒/波/防），GDScript，未上架。
**这不是 Node/JS 工程：没有 `package.json`、没有 lint/format/typecheck、没有 `npm test`。** `.mcp.json` 只是 Godot MCP 桥接配置，别据此推断技术栈。

## 关键路径（别猜错）

| 用途 | 路径 |
|---|---|
| Godot 工程（唯一） | `D:\xiongxiong\xiongxiong` |
| Godot 4.7.2 console 引擎 | `C:\Users\pc\XiaomiMiMoProjects\xiongxiong\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| **文档 / 规则冻结稿** | `C:\Users\pc\XiaomiMiProjects\xiongxiong\docs\`（**在本仓库外**，见下） |

**路径坑（两处只差一个字母，极易踩）**：文档镜像在 `XiaomiMiProjects`，引擎在 `XiaomiMiMoProjects`（MiMo 双 M）。本仓库内**没有 `docs/`**，任何 `docs/...` 引用都指向镜像目录。

规则唯一权威是 `docs/rules/minimal-rules-v0.md`（**已冻结**）。其它：`docs/arch/peer-manager-multipath.md`、`network-session-fsm.md`、`quality-performance-tiers.md`、`docs/design/game-flow-v0.md`、`docs/testing/device-test-checklist.md`。

## 验证命令（改完必跑）

测试是 **Godot headless SceneTree 脚本**，`ALL PASS` + exit 0 = 通过：

```powershell
$g = "C:\Users\pc\XiaomiMiMoProjects\xiongxiong\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$g --headless --path D:\xiongxiong\xiongxiong --script res://tests/run_rules_check.gd
```

6 个自检，**全部都要跑**（`run_nav_check` 和 `run_netwindow_check` 是后来加的，交接文档里没列，别漏）：

`run_rules_check` · `run_network_check` · `run_seal_check` · `run_quality_check` · `run_netwindow_check` · `run_nav_check`

```powershell
# 一条命令跑完全部
foreach ($n in "run_rules_check","run_network_check","run_seal_check","run_quality_check","run_netwindow_check","run_nav_check") {
  & $g --headless --path D:\xiongxiong\xiongxiong --script "res://tests/$n.gd" > $null
  "$n exit=$LASTEXITCODE"
}
```

另有一个 Python 规则镜像测试：`python tests/test_rules_v0.py`。

建议顺序：先 `run_rules_check`（最快，纯逻辑）→ 按改动范围挑对应的 → 最后 `run_nav_check`（最重，会起双端联机+人机接管）。

## 硬约束

1. **`scripts/rules/*` 结算语义禁止口头改。** 改规则必须先变更记录走冻结流程。
2. **`tests/test_rules_v0.py` 是 `scripts/rules/resolve.gd` 的逐行镜像**（不是包装调用）。改了 resolve 必须同步改这个 Python 文件，否则两套结算表会静默分叉。
3. **房主权威**：`PeerManager`（autoload `Net`）里客户端只 apply 房主下发的结算，**绝不本地调 `GameResolve`**。
4. **竖版是契约**：`project.godot` 的 390×820 / `orientation=1` 与 `export_presets.cfg` 的 `screen/orientation=1` 必须同时成立，`run_nav_check` 会静态校验这两处。
5. **headless 下 `static func` 不能直接写 autoload 名**（如 `Net`），编译期解析不到。要像 `scripts/ui/ui_nav.gd` 那样运行时取：`Engine.get_main_loop().root.get_node_or_null("Net")`。
6. **新增 `class_name` 后必须重建 class cache**：`& $g --headless --path . --import`，否则其它脚本报"标识符未声明"。`.godot/global_script_class_cache.cfg` 即该索引。
7. 脚本旁的 `*.gd.uid` 已入库，勿删勿手改。
8. 文案规范：角色只用**「我 / 对手」**，禁用颜色昵称；规则出处不可考，统一写**「致敬童年」**，不写「完整还原」。

## 架构边界

- `scripts/rules/` — `GameRules` / `BattleState` / `GameResolve`，**纯逻辑，禁止耦合 UI、画质、网络**。
- `scripts/network/` — `NetworkProvider` 抽象 + `LocalProvider`（测试/热座）/ `EnetProvider`（真联机）/ `WebSocketProvider`（抖音预留桩）。
- `scripts/session/` — `PeerManager`(autoload `Net`)、`BattleController`（单机）、`NetworkedBattleController`、`NetworkSessionFSM`（断线封存 7 态）、`AiOpponent`。
- `scripts/performance/` — `QualitySettings`(autoload) + `FpsGuard`，**只动表现层**（帧率/特效/降采样），不读写 rules 与对局状态。
- `scripts/ui/` — `menu` / `main`(单机) / `net_battle_ui` / `settings_panel` / `ui_nav`(导航) / `ui_theme` / `battle_fx`。
- `scenes/` — `menu.tscn` 是 `run/main_scene`，入口从这里开始。
- `build/` **部分是源码**：`export_android.ps1`、`dl_font.py` 在里面；但 `xiongxiong-debug.apk`（约 73MB）被 git 跟踪，改动会刷出巨大的 diff，提交前留意。

## Android 导出

```powershell
.\build\export_android.ps1 -CheckOnly   # 只查环境，不导出
.\build\export_android.ps1              # debug APK
.\build\export_android.ps1 -Release     # release APK
```

包名 `com.xiongxiong.demo`，产物 `build/xiongxiong-debug.apk`。前置依赖：Godot 4.7.2 导出模板（`%APPDATA%\Godot\export_templates\4.7.2.stable`）、JDK 17 + `JAVA_HOME`、Android SDK（`ANDROID_HOME`，platform-tools + build-tools 34.x）、debug keystore（`%APPDATA%\Godot\keystores\debug.keystore`）。`-CheckOnly` 会逐项告诉你缺什么。安装：`adb install -r build\xiongxiong-debug.apk`。

## Godot MCP（重要）

`addons/godot_mcp_toolkit` 是**编辑器内插件**，`.mcp.json` 里的 npm 桥（`npx -y @npgamedev/godot-mcp-server`）只跟**编辑器里当前打开的工程**通信。要让它作用到本仓库，**必须先在 Godot 编辑器里打开 `D:\xiongxiong\xiongxiong`**，否则工具会连到别的工程实例上（甚至另一个 MCP runtime 端口 6570–6585）。改场景/UI/脚本优先走 MCP，而不是手写 `.tscn`。

## 工作约定

- 终端用 **PowerShell 7 (pwsh)**；跑自检时直接调引擎并读 `$LASTEXITCODE`（需要退出码时才这样，一般交互式启动用 `Start-Process`）。
- 仓库↔镜像同步用 **`cmd xcopy`**，`Copy-Item` 可能静默失败。
- 大改动先拆 subagent；派单时写清工程路径、禁止改 `scripts/rules/*`、验收命令。

## 当前未提交改动（勿直接覆盖/提交）

`scripts/session/networked_battle_controller.gd`（rematch/restore 时重新拉起 `_running`）、`scripts/ui/net_battle_ui.gd`（血/气图标行改从列 meta 取，不再按座位下标选行），以及重新导出的 debug APK。

## 交接文档

`SESSION-HANDOFF.md`（根目录，与镜像 `docs/SESSION-HANDOFF.md` 同内容）记录待办优先级与「节奏约定」。**其回归清单只列了 4 个 check，实际有 6 个**，以上方「验证命令」为准。
