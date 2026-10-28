# 会话交接 · 拍拍熊熊（xiongxiong）· 2026-10-14 深夜

> 新会话请读完本文再动手。工程 Godot **4.7.2**，竖版 1v1「攒/波/防」demo。
> **2026-10-17 更新**：联机 P0（断线封存死锁 / 房主权威 / 网络误报）已修并提交 `c106e21`，自检断言 199→241。**MVP 基线到此为止**，下一阶段开始加功能/模块/前端页面。

---

## 1. 工程与工具

| 用途 | 路径 |
|---|---|
| Godot 工程 | **仓库根目录**（命令一律 `--path .`，不写绝对路径） |
| Godot 控制台 | `$env:GODOT` 或 `.\tools\run_checks.ps1` 自动探测（本机路径见 `docs/ENVIRONMENT.md`） |
| 导出脚本 | `pwsh -File build\export_android.ps1`（环境自检 + 自动探测 JDK/SDK） |
| 环境一键配置 | `pwsh -File build\setup_android_env.ps1`（把 JDK/SDK 路径写进 Godot 编辑器设置；先关编辑器） |
| APK | `build\xiongxiong-debug.apk`（约 70MB，含 CJK 字体） |
| 远端 | `https://github.com/HapyRain/xiongxiong`（**必须走本机代理 `127.0.0.1:7897` + `-c http.sslBackend=openssl`**） |
| 文档镜像 | 旧机过程文件未随仓库迁移、不再依赖；规则权威 = `docs/rules/game-rules-v2.md` |

**回归（改完必跑，8 个；统一走 `.\tools\run_checks.ps1`）：**
```
run_rules_check / run_quality_check / run_network_check / run_seal_check /
run_netwindow_check / run_roundloop_check / run_nav_check / run_ui_check
```
命令：`.\tools\run_checks.ps1`（一条跑完 8 自检 + Python 镜像；只跑部分：`-Only ui,nav`；手动单跑用 `& $env:GODOT --headless --path . --script res://tests/run_XXX_check.gd`）

**注意：** headless 测不出布局/聚光灯/真机字体类问题，必须 F5 真窗口 + 双机验证。

---

## 2. 冻结规则（勿改 `scripts/rules/*` 结算）

- **规则唯一权威 = `docs/rules/game-rules-v2.md`（已定稿）**：血 4 / 盾 3 / 气 10、12 分制、11 技能 + 劝降、对撞矩阵、六步结算管线、平局保底（第 3 次起各 +1）。本文件不再复述数值，防止两处漂移。
- 2 拍节奏：输入窗 ≈**3.0s**（`battle_tempo.gd`：基础 2.85s，每 5 回合 -0.12s，40 回合时 ≈2.16s）；开局窗同 3.0s。旧文档写的「窗口 5s / 开局窗 6s」已过期（`OPENING_SELECT_WINDOW=6.0` 只进广播 payload，实际节奏走 BattleTempo）
- 角色文案只用「我 / 对手」，形象是熊

---

## 3. 当前已具备

- 单机人机、ENet 联机（发现/加入/接受/对局）、断线人机接管、封存恢复、再来一局
- **断线封存走真实路径**：掉线先封存保住完整快照（rules+session、双方都收到），再转人机接管保持可玩
- **房主权威**：只接受唯一对端的数据包；客户端不能替房主出招、不能宣布胜负、不能改快照
- **网络质量判定**：丢包窗口 2.5×心跳间隔；延迟/抖动连续 2 次超标才降级（局域网不再误报「网络不佳」）
- 竖版 UI（1080×1920，v3 三渲二升级起），两页首页（单人 / 联机），设置面板
- 中文 Noto 字体打包；血气盾图标行；亮招卡片、命中/格挡/受击/胜负特效
- 开局聚光灯引导点「攒」
- Android 权限 / MulticastLock / 多网卡 IP / create_host 绑定回退

---

## 4. 最近已修（本轮）

| 问题 | 状态 |
|---|---|
| 联机双方血气盾对调 | 按 `local_role` 显示，图标挂在 panel meta |
| 开局 2 气（应 1） | `resolve_opening` 只准结算一次 |
| 新一局继承上一局血气 | `host/join/leave/start_battle` 里 `_reset_rules_state()` |
| 第二回合全变「防」 | 超时默认优先 `state.pending` 点选 |
| 点招后像没点上、等超时 | **点击立刻 submit 锁定**；UI 与单机一致变灰 |
| 再来一局面板残留/无特效 | 双方 `rematch_answered` 收遮罩；特效层置顶 |
| 聚光灯挖空在左上角 | 等两帧布局稳定 + `item_rect_changed` 自愈 |
| 设置 ✕ / 点外关闭 / 确认框看不清 | ✕ 在标题行右侧；点遮罩关闭；UiTheme Label 默认深字 |

**2026-10-28（v3 1080P 三渲二合入）**

| 问题 | 修法 |
|---|---|
| v3 交付包 `other/v3.0` review 并入 | 15 文件 + 68 资源并入；`scripts/rules/*` 与 Python 镜像零改动 |
| 视口契约 390×820 → 1080×1920 | `project.godot` + `run_nav_check` 同步（竖版 orientation=1 不变） |
| `battle_fx.gd` 编译错（Python 语法 `//`） | 改 `/`；8 自检全绿 |
| 交付包声称的 6 张贴图实际缺失 | 程序化占位图补上（`stage_bg_cel` / `avatar_bear_*` / `vfx_*_cutin` / `rope_spark`），美术同名替换即可 |
| 战报文案「敌」违反「我/对手」规范 | 统一改「对手」 |
| `quality_settings` 原子写/`fps_cap` 键被回退 | 恢复 tmp+rename 原子写与 `fps_cap` 键 |

**2026-10-17（`c106e21`）**

| 问题 | 修法 |
|---|---|
| 断线/心跳抖动后局面清零 + 永久卡死 | 自主封存改带真实 rules+session；恢复按快照复位 opening 标记；封存统一广播 |
| 对端可单包判房主负 / 改房主局面 / 替房主出招 | 发送者白名单（唯一对端）+ 房主/客户端方向守卫 + 座位校验 |
| 局域网误报「网络不佳」 | 丢包窗口 1×→2.5× 间隔；延迟/抖动需连续 2 次超标；抽 `hb_miss_due()` 可测边界 |
| 菜单页双齿轮 / 设置面板可叠加 | 判重改 group 查询（面板会搬进 `SettingsPanelLayer/`，原路径查不到） |
| 联机 UI 每帧重建 26 个 StyleBoxFlat | pip 样式按「亮灭+颜色+尺寸」缓存 |
| 聚光灯两条运行时报错（tree_exiting 转换失败 / Infinite loop） | 改绑 `instance_id`；重建前 kill 循环 tween + 目标失效守卫 |
| 自检假绿（断言 199 条但删实现仍全绿） | 断言 199→241：补赢法/封顶/40 回合/`can_use_action`、封存快照、伪造包、健康链路不误报 |

---

## 5. 已知风险 / 下一步建议

1. ~~缺「点招→双方→亮招→下一回合」自动闭环测试~~ **已补**：`tests/run_roundloop_check.gd`（3000d5e），含 rematch
2. **ENet 自动重连未实现**：断线=封存+人机接管；「重连→双方同意→3s 倒计时→恢复」只差传输层重连握手（FSM 那套已写好，约半天到一天）
3. **规则层不校验输入**：`resolve_turn` 对非法/资源不足出招会静默按 clamp 算；`resolve_opening` 连调两次会二次加气（幂等靠调用方守卫）。改这两条要走冻结流程，并同步 `tests/test_rules_v0.py`
4. 搜索房间在部分 ROM 上仍可能失败（子网广播按 /24 猜；AP 隔离）
5. CJK 字体未子集化，APK 偏大（可 `pyftsubset` 瘦 15MB+）
6. 联机拍2 与「点击即锁定」节奏需产品确认：当前点完就锁，拍2 只亮招
7. 真机双端 ENet + 断网封存 + 再来一局 仍要完整走一遍（2026-10-17 用户已真机试玩，体感无阻塞 bug）

---

## 6. 工作约定（请继续遵守）

- 不改 `scripts/rules/*` 结算语义
- 优先 Godot MCP；大块可派 subagent。**模型路由以当前会话注册为准**（本机 DSH 只注册了 `deepseek-official/deepseek-flash` 与 `longcat`；旧机写的 `zhipuai/glm-5.3-flash` / `alibaba-cn/qwen3.8-flash` 在本机不可用）
- UI/网络静默 bug：先写复现测试再改；改完测试先确认「删掉对应实现它会不会红」
- 提交用**显式路径**（不要 `git add -A`，APK 73MB）；沙箱写 `.git/` 被拒（`index.lock: Permission denied`）时用一次性 `danger-full-access`，或请用户在外部终端提交
- 打包后请用户真机/F5 确认再推远端
- 推送：`$env:HTTPS_PROXY="http://127.0.0.1:7897"; git push origin main`
- 中文短句汇报

---

## 7. 新会话开场（可直接贴）

```text
读取仓库根目录 SESSION-HANDOFF.md，按「已知风险/下一步」继续。

当前最优先：
1) **MVP 基线已达成**（8 自检全绿 / 784 断言 / 头部 `2190e2f` + 未提交 review 修复批次）；下一阶段按需求加功能、模块、前端页面
2) 真机回归：搜索/建房/接受/对局/再来一局/断线（用户已试玩体感 OK，现阶段只需确认没退化）
3) 需要视觉或复杂联机问题时拆 subagent 分工（模型路由以当前会话注册为准）

约束：不改 scripts/rules/* 结算；改完跑 `.\tools\run_checks.ps1`（8 项）；打包 build/export_android.ps1；推送走 127.0.0.1:7897 代理。
```
