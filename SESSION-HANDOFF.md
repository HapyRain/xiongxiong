# 会话交接 · 拍拍熊熊（xiongxiong）· 2026-10-14 深夜

> 新会话请读完本文再动手。工程 Godot **4.7.2**，竖版 1v1「攒/波/防」demo。

---

## 1. 工程与工具

| 用途 | 路径 |
|---|---|
| Godot 工程 | `D:\xiongxiong\xiongxiong` |
| Godot 控制台 | `C:\Users\pc\XiaomiMiMoProjects\xiongxiong\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| 导出脚本 | `pwsh -File build\export_android.ps1` |
| APK | `build\xiongxiong-debug.apk`（约 70MB，含 CJK 字体） |
| 远端 | `https://github.com/HapyRain/xiongxiong`（**必须走本机代理 `127.0.0.1:7897`**） |
| 镜像 | `C:\Users\pc\XiaomiMiProjects\xiongxiong\` |

**回归（改完必跑）：**
```
run_rules_check / run_network_check / run_seal_check /
run_quality_check / run_nav_check / run_netwindow_check
```
命令：`& $Godot --headless --path D:\xiongxiong\xiongxiong --script res://tests/run_XXX_check.gd`

**注意：** headless 测不出布局/聚光灯/真机字体类问题，必须 F5 真窗口 + 双机验证。

---

## 2. 冻结规则（勿改 `scripts/rules/*` 结算）

- 气 0–5，血 5，盾 0–3；40 回合比血
- 回合 1 开局亮相：气+1、盾=3（`resolve_opening`）
- 攒：气+1盾+1；波：耗 1 气；防：成功格挡才扣 1 盾
- 2 拍节奏，窗口约 5s；开局窗 6s
- 角色文案只用「我 / 对手」，形象是熊

---

## 3. 当前已具备

- 单机人机、ENet 联机（发现/加入/接受/对局）、断线人机接管、封存恢复、再来一局
- 竖版 UI（390×820），两页首页（单人 / 联机），设置面板
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

---

## 5. 已知风险 / 下一步建议

1. **缺「点招→双方→亮招→下一回合」自动闭环测试**（`run_netwindow` 只覆盖开局窗口）
2. 搜索房间在部分 ROM 上仍可能失败（子网广播按 /24 猜；AP 隔离）
3. CJK 字体未子集化，APK 偏大（可 `pyftsubset` 瘦 15MB+）
4. 联机拍2 与「点击即锁定」节奏需产品确认：当前点完就锁，拍2 只亮招
5. 双机 ENet + 断网封存 + 再来一局 仍要真机走一遍

---

## 6. 工作约定（请继续遵守）

- 不改 `scripts/rules/*` 结算语义
- 优先 Godot MCP；大块可派 subagent（**模型用 `zhipuai/glm-5.3-flash` / `alibaba-cn/qwen3.8-flash`**，点根因比单模型准）
- UI/网络静默 bug：先写复现测试再改
- 打包后请用户真机/F5 确认再推远端
- 推送：`$env:HTTPS_PROXY="http://127.0.0.1:7897"; git push origin main`
- 中文短句汇报

---

## 7. 新会话开场（可直接贴）

```text
读取 D:\xiongxiong\xiongxiong\SESSION-HANDOFF.md，按「已知风险/下一步」继续。

当前最优先：
1) 补一条联机闭环回归（点招→双方→亮招→下一回合，含 rematch）
2) 真机走通：搜索/建房/接受/对局/再来一局/断线恢复
3) 需要视觉或复杂联机问题时，派 glm-5.3-flash 与 qwen3.8-flash 双审

约束：不改 scripts/rules/* 结算；改完跑全部 run_*_check；打包 export_android.ps1；推送走 127.0.0.1:7897 代理。
```
