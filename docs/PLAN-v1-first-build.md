# PLAN v1 · 初版全功能（前端占位）

> 目标：把**除真实视觉之外**的所有东西做完，形成可玩初版：双模式（经典/课间）、单人难度、技能精通、联机房间/搜索/准备/倒计时、页面跳转与占位 UI；随后两轮多方审计、两轮迭代、打包、推送。
> 执行方式：**Lead 只派发与复核，不写实现**；实现由 subagent 完成，每个任务写清 write scope + 验收命令，回报 ≤8 行。

---

## 0. 非目标（本次不做）

- 真实视觉/美术/动效（用占位块代替）
- 音效/震动打磨（保留现有）
- 自动重连（ENet reconnect）、host migration 真迁移（用 fallback 提示）
- 抖音/WebSocket 对战
- 新规则/新技能

## 1. 模式规格（已定，来自两份规则页）

| | 经典模式 | 课间模式 |
|---|---|---|
| 规则页 | `docs/rules/game-rules-classic.md` | `docs/rules/game-rules-v2.md` |
| 血/气/盾上限 | 1 / 5 / 3 | 4 / 10 / 3 |
| 包子连数 | 1 | 1–3 |
| 动作 | 攒 / 包子 / 防御 | 11 技能 + 劝降 |
| 技能解锁 | 无 | 1–8 分依次解锁；精通开启则开局满技能且后续不再解锁 |
| 胜负 | 一局定胜负 | 先到 12 分 |
| 40 回合 | 比血（血同平） | 比血（血同平） |
| 平局 | 重开一局 | 第 3 次起双方各 +1 |

**技能精通（课间专用开关）**：开启 → 双方开局解锁全部技能（相当于 8 分状态）；小局胜负不再解锁；比分与胜负规则不变。

## 2. 工作分解（每个任务一个 agent，写作用域不重叠）

### W1 · 规则层模式预设（owner A）

- `scripts/rules/game_rules.gd`：加 `Mode` 枚举与预设（classic/lesson）；参数集中于预设：max_hp/max_qi/max_shield/bao_max/可用动作/skills_enabled/score_to_win/opening
- `scripts/rules/battle_state.gd`：按预设读参数；`available_actions` 过滤；`reset_round_keep_score` 兼容 classic（一局定胜负）
- `scripts/rules/resolve.gd`：只在"包子连数上限 / 可用动作"处读预设（矩阵本身不改语义）
- `tests/test_rules_v2.py`：镜像两种预设（classic 参数表 + 关键用例）
- `tests/run_rules_check.gd`：补经典模式断言（单包子、防御耗盾、包子打攒即死、40 回合平、精通开局满技能）
- 验收：`.\tools\run_checks.ps1 -Only rules,py` 全绿；变异测试：把 classic.max_hp 改回 4 必须变红
- **禁改**：任何现有课的结算语义（矩阵分支、CD 语义、劝降条件）

### W2 · 对局流程与模式接线（owner B，依赖 W1）

- 单机：模式/难度选择 → 开局（classic 一局定胜负；lesson 12 分制；精通开关）
- `scripts/session/battle_controller.gd`：接收 match config（mode/difficulty/mastery）
- AI 难度：`ai_opponent.gd` 加 `normal` / `hard` 两档（normal=现权重；hard=惩罚"对方连续攒气"、更爱用包子压裸攒）
- 验收：`run_roundloop_check` + `run_nav_check` 全绿；补 2 条断言（classic 一局结束整场结束；mastery 解锁旁路）（勘误 10-27：原写"mastery 开局 13 动作全可用"——CD 仍按开局计时，实为第 2 回合 6 动作 / 第 9 回合 13 动作）

### W3 · 联机房主/搜索/准备/倒计时（owner C，依赖 W1，可与 W2 并行）

- 房间模型：名称（默认 `OS.get_model_name()` + 模式 + 精通后缀"·精通"）、模式、精通、房主/客户端座位
- 房主：创建房间 → 选模式/精通 → 进入等待页（本方=已准备？统一"双方都要点准备"）
- 搜索：扫描局域网房间（复用现有 discovery），列表/空态/失败提示（未连热点、无房间、搜索超时）
- 加入：选中房间 → 房主收到"加入请求" → 同意/拒绝（只保留一个确认弹窗）
- 等待页：双方未准备 → 各自准备 → 双方准备后 **5s 倒计时** → 同步开局
- 离开：任意方离开 → 对方回到"创建/加入"页并提示
- **房主离开**：客户端显示"房主已离开，请重新选择模式"（单确认键）→ 回"创建/加入"页（不做 host migration）
- 验收：`run_network_check` + `run_netwindow_check` + `run_seal_check` 全绿；补断言（房间名默认格式、双准备后 countdown、房主离开回落、搜索空态）
- 禁改：房主权威原则（客户端不本地结算）

### W4 · 页面与占位 UI（owner D，依赖 W2/W3 的接口；可先搭骨架）

- 页面（每屏一个 `.tscn` + 脚本，全部占位）：
  1. Splash：加载占位块 + 文案 `【占位】加载动画` + "进入游戏"按钮（点击前确保资源就绪）
  2. 主菜单：单人 / 联机 / 设置 / 退出
  3. 单人模式选择：经典 / 课间 两张卡 + 难度（普通/困难）+ 精通开关（课间）+ 开始
  4. 联机入口：作为房主 / 搜索房间
  5. 创建房间：模式 + 精通 → 等待页
  6. 搜索房间：搜索中/列表/空态/失败 四种状态 + 加入
  7. 等待页：双座位（空座/已座）、准备按钮、5s 倒计时、离开
  8. 对战：按模式渲染（classic 3 按钮；lesson 技能盘），资源条/分数条/回合/揭示区全部占位块
  9. 小局结算：比分/解锁提示（占位）
  10. 终场：胜者、再来一局/返回（占位）
  11. 设置：沿用现有面板
  12. 断线/封存 overlay：占位提示
- 占位规范：统一 `ColorRect + Label("【占位】xxx")`；颜色用主题色；尺寸用锚点；**每屏单屏不滚动、390×820**
- 后端接线：所有按钮真实可用（跳转/选择/开始/准备/离开），只有视觉是占位
- 验收：`run_nav_check` 全绿（含竖版契约、overlay 清理）；新增 UI 冒烟测试：依次加载各宿主屏若干帧，**0 ERROR**（第 8 个自检）（勘误 10-27：原计划 12 屏，实现为 8 个宿主场景——Splash/小局结算/终场/断线 overlay 为宿主内嵌覆盖层，随宿主验证）
- 禁改：`scripts/rules/*`、`scripts/session/*` 的结算逻辑；UI 只读 state + 发意图

### W5 · 集成验收（Lead）

- 全量 `.\tools\run_checks.ps1`（8 项，含新 UI 冒烟）
- 变异测试 2 处（classic 参数、mastery 解锁）
- 两份规则页与实现一致性抽查（矩阵用例样本）
- 生成 APK：`.\build\export_android.ps1`（注意会顶掉编辑器 MCP）
- 提交（显式路径）+ 推送（代理 + sslBackend=openssl）

### W6 · 两轮审计 + 两轮迭代

- 第一轮：plan 审计（GLM / Qwen / DeepSeek）→ Lead 汇总 → 迭代 plan
- 第二轮：coding 审计（同三家，读实现与测试）→ Lead 汇总 → 派修复 → 复核 → 提交

## 3. 依赖与并行

```
W1 ──> W2 ──> W4 ──> W5
  └──> W3 ──> W4
```
- W1 单独跑（规则层，风险最高）
- W2 与 W3 可并行（写作用域不同）
- W4 在 W2/W3 接口定型后并行做页面（可先搭全部骨架，再接线）
- W5/W6 由 Lead 串行

## 4. 占位 UI 规范（便于后期替换）

- 每个占位块命名 `Placeholder_<用途>`，脚本里有 `# TODO(ui): 替换为真实 <>` 注释
- 占位文案统一 `【占位】<内容>`，方便全局搜索替换
- 所有占位块用主题色，不写死尺寸（锚点 + container）
- 真视觉替换时只改 `.tscn`/主题，不动脚本逻辑

## 5. 自审（Lead 出的风险清单）

| 风险 | 处理 |
|---|---|
| 范围大，一次做完易失控 | 分 W1–W4 四个独立 agent，每个有明确 write scope 与验收命令；失败只重派该任务 |
| 规则层加参数会碰"冻结流程" | 只加参数预设，不改矩阵语义；同步 Python 镜像 + 断言 + 变异测试 |
| W2/W3 同时改 `peer_manager.gd` → 冲突 | W3 独占 `peer_manager.gd`；W2 只改 `battle_controller.gd` / `ai_opponent.gd` |
| W4 依赖接口未定 | 先定 MatchConfig 结构（W1 输出），W4 按结构写占位 |
| 8 个自检 + 新 UI 冒烟可能长 | 冒烟只加载 8 个宿主屏 ×60 帧（勘误 10-27，原 12 屏）；跑全量约 3–5 分钟，可接受 |
| APK 构建会顶掉编辑器 MCP | 放在最后，构建后提醒用户重启编辑器 |
| 提交时 `.git` 被沙箱拒 | danger-full-access 提权，或用户外部提交 |
| 占位块被误当成品 | 所有占位带 `【占位】` 文案 + TODO 注释 + 本文件说明 |

## 6. 验收门槛（Definition of Done）

1. 8 个自检全绿（7 旧 + UI 冒烟），Python 镜像 ALL PASS
2. 两处变异测试能变红
3. 经典/课间/精通三种配置都能从主菜单走到终场
4. 联机：房主创建 → 客户端搜索加入 → 双方准备 → 5s 倒计时 → 开局 → 打完 → 再来一局；房主离开 → 客户端提示并回入口
5. APK 构建成功，`build/xiongxiong-debug.apk` 更新
6. 显式路径提交 + 推送成功

## 7. 上下文与汇报纪律（给所有 agent）

- 先读：`AGENTS.md`、本文件、`docs/rules/game-rules-v2.md`、`docs/rules/game-rules-classic.md`
- 不读无关大文件；不打印整篇文件
- 完成回报 ≤8 行：改了什么 / 验收结果 / 风险 / 下一步
- 遇到规则歧义：不改规则，按文档字面实现并记录假设，报给 Lead

---

# PLAN v1.1 · 审计后修订（开工依据）

> 本文件与上方 v1 冲突时，以 v1.1 为准。审计来源：GLM / Qwen / DeepSeek 三方。

## R1. 规则层预设字段（固定）

`GameRules.Preset`（Dictionary，禁止新增 class_name）：

```
mode: "classic" | "lesson"
max_hp / max_qi / max_shield: int
bao_max: int                     # classic=1, lesson=3
actions: Array[int]              # 允许动作；classic=[ZAN,BAO1,FANG]
skills_enabled: bool             # classic=false：不劝降、不技能、不看解锁分
quan_jiang_enabled: bool         # classic=false
draw_backstop: bool              # classic=false；lesson=true（第3次平局各+1）
score_to_win: int                # classic=1, lesson=12
round_cap: int                   # 40
cap_rule: "hp_then_draw"         # 两模式一致：比血，血同判平
draw_replay_max: int             # classic 专用：平局后重开本局，最多 3 次；第4次平局整场判平
```

**精通 = 会话选项，不是规则**：`match.mastery`（bool）写进对局配置；规则层只在 `can_use_action` 的解锁分支上旁路（mastery=true 视为已解锁全部），并且**不再累加解锁**；不走解锁分。snapshot 必须带 `mastery`。

**classic 三条边界（写进规则页）**：

1. 盾 0 出防御 = 非法 → 按裸防结算（掉 1 血，即负）
2. 40 回合双方存活 → 平局；classic 平局 = **重开本局**（不清场），最多 3 次；第 4 次整场判平回菜单
3. 劝降、平局保底、技能解锁在 classic 全部关闭

## R2. MatchConfig 与联机协议（W1/W3/W4 共用）

**MatchConfig**（Dictionary）：

```json
{ "mode": "classic|lesson", "mastery": false, "difficulty": "normal|hard" }
```

- 单人：UI 选择 → `BattleController.start_match(cfg)`（新增公开 API；`_ready` 不再自动开局）
- 联机：房主保存 cfg；`battle_start` payload 增加 `"config": cfg`；客户端收到后写入 `BattleState` 再开局
- 快照：`snapshot.rules` 增加 `mode`、`mastery`；`restore` 校验与房主一致，不一致 → 拒绝并返回入口
- 客户端 `_reset_rules_state()` 必须按 room cfg 构造，不允许默认 lesson

**房间模型**：

```json
{ "room_id": str, "name": str,        // 默认 "<机型> · <经典|课间>[ · 精通]"
  "mode": str, "mastery": bool, "host_name": str, "players": int, "max": 2 }
```

**新增消息**（沿用 `{v,type,round,from_role,payload}` 信封）：

| type | 方向 | payload |
|---|---|---|
| `room_announce`（扩展现有发现包） | 房主→广播 | +`mode`、`mastery` |
| `join_request` | 客户端→房主 | `{name}` |
| `join_answer` | 房主→客户端 | `{yes}` |
| `room_state` | 房主→客户端 | `{room, host_ready, client_ready}` |
| `ready` | 双向→房主 | `{yes}` |
| `countdown_start` | 房主→客户端 | `{remain_ms:5000}` |
| `leave_room` | 双向 | `{}`（未开局） |

**离开语义（分阶段，避免与人机接管冲突）**：

- LOBBY / READY_CHECK / COUNTDOWN 阶段离开 → 对方提示"房主/对方已离开" + 回"创建/加入"页
- IN_BATTLE 阶段离开 → **保持现状**（封存 → 人机接管），不改
- 房主离开（未开局）：客户端单确认键回入口（不做 host migration）

## R3. 任务重划（write scope 到文件，禁止越界）

| 任务 | 文件白名单 | 依赖 |
|---|---|---|
| **W0 UI 底座** | `scripts/ui/ui_placeholder.gd`(新)、`scripts/ui/ui_nav.gd`、`scripts/ui/ui_theme.gd`、`tests/run_ui_check.gd`(新)、`tools/run_checks.ps1` | 无 |
| **W1 规则预设** | `scripts/rules/*.gd`、`tests/test_rules_v2.py`、`tests/run_rules_check.gd` | 无 |
| **W2 单人流程** | `scripts/session/battle_controller.gd`、`scripts/session/ai_opponent.gd`、`scripts/ui/main.gd`、`scenes/main.tscn`、`scenes/solo_select.tscn`(新)、`tests/run_roundloop_check.gd` | W1 |
| **W3 联机流程** | `scripts/network/*`、`scripts/session/peer_manager.gd`、`scripts/session/networked_battle_controller.gd`、`scripts/ui/menu.gd`、`scenes/menu.tscn`、`scripts/ui/net_battle_ui.gd`、`scenes/lobby_*.tscn`(新)、`tests/run_network_check.gd`、`tests/run_netwindow_check.gd`、`tests/run_seal_check.gd` | W1 |
| **W4 Lead 集成** | 无（只验证/提交） | W0–W3 |

- `run_nav_check.gd` 唯一 owner = W2（主场景/Splash 相关断言在 W2 里改）
- `AGENTS.md`、`SESSION-HANDOFF.md` 唯一 owner = W4（7→8 自检、HEAD 更新）
- **Splash 不换主场景**：`menu.tscn` 仍是 `run/main_scene`；Splash 作为 menu 内最上层 overlay（加载占位 + "进入游戏"按钮），不破坏 `run_nav_check` 断言
- 所有新屏必须注册到 `UiNav` 的 back-target 表；W0 提供 `NOTIFICATION_WM_GO_BACK_REQUEST` 统一处理（逐级回退，对战页二次确认）

## R4. 自检与验收（修正）

- 第 8 个自检：`tests/run_ui_check.gd`（`-Only ui`），加载静态屏 + 用 LocalProvider 装入 Net 后加载联机屏，各 60 帧
- **0 ERROR 判定**：`run_checks.ps1` 必须 `2>&1` 捕获输出并 grep `SCRIPT ERROR|^ERROR`，不能只看 exit code（否则假绿）
- `tools/run_checks.ps1` 的 `$all` 增加 `ui`；AGENTS / SESSION-HANDOFF 的"7 个自检"改 8 个（W4 统一改）
- 倒计时必须可注入时钟：`debug_tick_countdown(ms)`；5s 倒计时断言放 `run_netwindow_check`，不依赖真实时钟
- mastery 断言：第 2 回合 6 动作可用、第 9 回合 13 动作全可用（第 1 回合只放行攒气）（勘误 10-27：原写"第 2 回合 13 动作全可用"与 CD 开局计时矛盾，实现按 CD 规则正确）
- 变异测试至少两处：classic.max_hp→4 必红；mastery 旁路删掉必红

## R5. 提交白名单（W4）

- 提交：`docs/PLAN-v1-first-build.md`、`docs/rules/game-rules-classic.md`、`docs/rules/game-rules-v2.md`（若改）、`scripts/**`、`tests/**`、`tools/run_checks.ps1`、`scenes/**`、`AGENTS.md`、`SESSION-HANDOFF.md`
- **不提交**：`build/xiongxiong-debug.apk`（构建产物留工作区，按既有约定不入库）、`docs/ENVIRONMENT.md`、`docs/rules/*` 里的调研类文件（v1/handbook 等）
- APK 构建成功后单独报告路径，不入提交
