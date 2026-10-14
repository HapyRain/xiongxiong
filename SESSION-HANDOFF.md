# 会话交接 · 拍拍熊熊（xiongxiong）· 2026-10-14

> 给新会话用：读完本文按「下一步」继续。节奏约定见文末。

---

## 1. 项目一句话

童年「波波攒 / 拍拍熊熊」做成移动端 1v1 回合指令对战（攒/波/防），Godot 4.7，广告变现向；长期迁抖音小游戏。当前阶段：**单机/联机 demo 抛光**，未上架。

## 2. 关键路径

| 用途 | 路径 |
|---|---|
| **Godot 工程（主）** | `D:\xiongxiong\xiongxiong` |
| 文档镜像 / 旧工程 | `C:\Users\pc\XiaomiMiProjects\xiongxiong\`（docs + godot 副本） |
| Godot 引擎 | `C:\Users\pc\XiaomiMiMoProjects\xiongxiong\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（注意 **MiMo 双 M**；用 Start-Process 调用） |
| 已导出 APK | `D:\xiongxiong\xiongxiong\build\xiongxiong-debug.apk`（约 55MB，包名 `com.xiongxiong.demo`） |
| 冻结规则 | `docs/rules/minimal-rules-v0.md`（**已冻结 2026-10-14**） |
| 流程 | `docs/design/game-flow-v0.md` |
| 网络架构 | `docs/arch/peer-manager-multipath.md` |
| 断线封存 FSM | `docs/arch/network-session-fsm.md` |
| 画质分档 | `docs/arch/quality-performance-tiers.md`、`quality-settings-usage.md` |
| 规则调研 | `docs/research/game-rules-research.md` |
| 真机清单 | `docs/testing/device-test-checklist.md` |
| 环境 | JDK `C:\Users\pc\AppData\Local\Programs\Eclipse Adoptium\jdk-17.0.20.8-hotspot`；SDK `C:\Users\pc\AppData\Local\Android\Sdk`；debug keystore 已生成 |

**Godot MCP**：已接通（新会话）。插件连的是编辑器里打开的工程，应打开 **D:\xiongxiong\xiongxiong**。

## 3. 已冻结 Demo 规则（勿口头改）

- 1v1 同步出招：**攒 / 波 / 防**
- 资源：**气 0–5**，**血 5**，**盾耐久 0–3**（移动端新增）
- **回合 1 强制「攒」**：双方气 +1、盾补满 3；第 2 回合起正式博弈（产品已要求改为**玩家点击**才算开始，见待办）
- **攒**：气 +1、盾 +1（均封顶）；**波**：耗 1 气，对撞/命中；**防**：需盾 ≥ 1，**成功格挡** 才扣 1 盾，空防不扣
- 0 盾 **禁用「防」**（无软着陆）
- 2 拍节奏选招（啪-啪-亮招），窗口约 5s；超时默认：盾≥1 防 / 盾=0 攒
- 胜负：血 ≤ 0 败；双亡平；**40 回合**比血，相同平
- 网络：超阈值**立即封存** → 双方同意 → **3s 倒计时**（房主绝对时刻）→ 快照恢复；拒绝/超时未恢复方判负（产品更希望对方掉线由 **AI 接管**，见待办）

改规则须变更记录，禁止口头改。结算表以 `minimal-rules-v0.md` §3 为准。

## 4. 工程结构（D:\xiongxiong\xiongxiong）

```
scripts/rules/          game_rules · battle_state · resolve     纯逻辑，勿与画质/网络耦合
scripts/network/        network_provider · local · enet · websocket 桩
scripts/session/        peer_manager(autoload Net) · battle_controller ·
                        networked_battle_controller · network_session_fsm
scripts/performance/    quality_settings(autoload) · fps_guard
scripts/ui/             menu · main(单机) · net_battle_ui · settings_panel
scenes/                 menu.tscn · main.tscn · net_battle.tscn · settings_panel.tscn
tests/                  test_rules_v0.py · run_rules_check · run_network_check ·
                        run_seal_check · run_quality_check · gen_sfx.py
assets/audio/           clap · ding · hit · block · zan
export_presets.cfg      Android com.xiongxiong.demo
build/export_android.ps1
```

**回归**（改完必须仍过）：`run_rules_check` / `run_network_check` / `run_seal_check` / `run_quality_check`。

## 5. 已完成能力

1. 冻结规则实现 + 单机 vs 简易 AI + 2 拍亮招 + 音效/卡片亮招动画  
2. 菜单：单机 / ENet 创建房间 / 加入(IP) / UDP 发现 / 设置  
3. **热座同屏双人**（产品要求**去掉**，见待办）  
4. PeerManager 双后端：Local / Enet / WebSocket 桩（抖音预留）  
5. 断线封存 7 态 FSM + SessionSnapshot(seq/checksum) + 同意/倒计时 UI  
6. 画质低/中/高 + 帧率 30/60/90/120 + 设置面板（自动+手动）  
7. Android 导出链路跑通，debug APK 可装真机  

## 6. 待办（按优先级，继续做）

### T18/T19 菜单与对局导航（上次实现被取消，**未完成**）
1. **去掉同屏双人/热座入口**（底层可留，UI 勿露出）
2. **全面竖版**（portrait；390×820 思路；export 里 android orientation=portrait）
3. **终局 →「返回菜单」**；菜单含**「退出游戏」**
4. **对局中右上角**可打开菜单：
   - 人机：可直接回菜单
   - 联机：文案正确（主动离开 / **对方离开 → 提示并由人机接管**，继续可玩）

### T20 视觉抛光（**未开始**）
1. **血**用图标（红心等），**气**用图标/设计，避免素条太丑  
2. **胜负庆祝**特效  
3. **命中 / 格挡 / 受击**特效（发波弹道、盾牌闪光等）  
4. **开局强制攒**改为**用户点击**才算开始；第 1 回合窗口可 **6s**；双方都点攒 = 正式开始信号  

### 其它
- 双机真机 ENet + 断网封存联调  
- Android MulticastLock / 二维码直连  
- 抖音品类与版号调研收口  

## 7. 工作节奏约定（本项目）

- **规则最小化 → 流程/概念图 → 反推 → 冻结**；不陷入改规则细节。  
- 产品拍板：热座+ENet 曾并行；双后端网络接口；画质自动+手动。  
- 实现：**优先分发 subagent / 用 Godot MCP**，少手写；派单写清工程路径、禁止改 `scripts/rules/*` 结算语义、验收命令。  
- Windows 终端优先 **PowerShell 7 (pwsh)**。  
- 调用 Godot 用 Start-Process；镜像同步用 **cmd xcopy**（Copy-Item 可能静默失败）。  
- 新增 `class_name` 后要 `--headless --import` 重建 class cache。  
- 角色文案：只用 **「我 / 对手」**，形象是熊，不用颜色昵称。  
- 角色/招式民间规则公开不可考 → 文案「致敬童年」，不写「完整还原 10 级」。  

## 8. 建议新会话开场（可直接贴）

```text
读取 D:\xiongxiong\xiongxiong 或 C:\Users\pc\XiaomiMiProjects\xiongxiong\docs\
（以及项目根目录若有 HANDOFF / 本交接说明）。

请按其中「待办 T18/T19 + T20」继续，遵守「工作节奏约定」：
- 优先用 godot-mcp-toolkit（工程 D:\xiongxiong\xiongxiong，编辑器已打开该工程）做场景/UI/脚本；
- 大块可再分 subagent；不要改 scripts/rules/* 结算语义；
- 做完跑 run_rules_check / run_network_check / run_seal_check / run_quality_check；
- 中文汇报，短句即可。

先复述你理解的待办优先级，再开工 T18。
```
