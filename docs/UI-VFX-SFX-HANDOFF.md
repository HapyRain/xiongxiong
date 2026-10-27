# 《拍拍熊熊》v2 视觉资产、全技能动效、音效与 MOBA 反馈交接指南

> **用途**：供后续本地开发或 Agent 接手时快速了解 `assets/ui/`、`assets/audio/` 以及 `scripts/ui/battle_fx.gd` / `scripts/ui/ui_theme.gd` 的挂载方式与替换规范。

---

## 1. 本轮解决的核心问题清单

1. **修复右上角「设置」与「菜单」按钮重合 Bug (`scripts/performance/quality_settings.gd`)**：
   * `QualitySettings` 原先在进入 `menu.tscn` 时挂了常驻 `CanvasLayer(layer=50)` 的 `SettingsButton`，且 `node_added` 使用了 `CONNECT_ONE_SHOT`，导致切入 `main.tscn` / `net_battle.tscn` 时未隐藏，与对局右上角的 `MenuBtn` 重合。
   * 现已改为持续监听场景切换：凡进入 `menu.tscn`、`main.tscn`、`net_battle.tscn`（均自带菜单/设置按钮），`SettingsEntryLayer` 自动隐藏，并将 `net_battle_ui.gd` 右上角菜单按钮规整至 `-68..-12`。
2. **MOBA 级中央偏上博弈反馈横幅 (`MobaBanner`) + 格挡/被格挡/吸收非对称演出 (`BattleFx.play_clash_director`)**：
   * **格挡成功侧**：金青双层圣盾扩环 + 上浮正反馈大字 `🛡️ 格挡成功！` / `⚡ 强防弹反！` + 高亢金属共鸣音 `block_success.wav`。
   * **被格挡侧（攻击受挫方）**：面板向后震退弹回（Recoil）+ 碎火粒子 + `💥 攻击被挡！` + 撞铁受挫音 `blocked_rebound.wav`，且包子投射物在命中护盾时会向侧面弹飞碎裂。
   * **吸收博弈**：吸收成功时从被偷方抽取 6 颗紫色能量球飞入吸收方（`xi_shou_ok.wav` + `🌀 吸收成功！偷取【XX】`）；吸收撞上攻击失败时触发黑洞内爆反噬（`xi_shou_fail.wav` + `💔 吸收反噬 -1血！`）；吸收撞上防御时提示 `💨 吸收落空`。
3. **右下偏中「5 轮打字机上推战报栏」(`BattleTicker`)**：
   * 位于中央舞台右下方（我方状态卡右上方，宽 `214px` × 高 `82px`），左侧并排放置拍点进度条。
   * 最多保留最近 **5 回合**交手记录（`R01`..`R40`），每回合结算时旧记录平滑向上推移并按远近阶梯淡化透明度（`0.42 → 0.82`），最新一条在最底部以**打字机逐字敲出效果**（`visible_ratio: 0.0 → 1.0`）呈现。
4. **按钮四态交互（Normal / Hover-Selected / Pressed / Disabled-Reject）**：
   * 每个技能按钮左上方挂载专属图标 `IconTex`，底层挂载状态遮罩 `StateTex`（冷却斜纹、未解锁锁框、封盾红链、选中金光）。
   * **禁用态可感知拒绝反馈**：当玩家在选招时点击处于 CD、未解锁、封盾或缺气的按钮时，触发水平拒绝抖动 `BattleFx.play_reject_feedback` + 拒绝音效 `ui_deny.wav` + 中央横幅提示具体原因（如 `⏳ 【小羊】冷却中（还需 2 回合）`）。
5. **随回合推进的「紧绷感」BGM (`bgm_battle.wav`) + 开局号角 (`game_start.wav`)**：
   * 开局自动播放 `game_start.wav` 并启动无缝循环的 `bgm_battle.wav`。
   * 每回合调用 `BattleFx.update_bgm_tension()`：随着回合数增加、任意一方残血（1 血）或临近赛点，平滑提升 BGM 的 `pitch_scale`（`1.00 → 1.30`）与音量（`-12 dB → -6.5 dB`），越到后期越紧迫。

---

## 2. UI 贴图资产目录 (`assets/ui/`) 与替换方式

当前已通过 `UiTheme.load_ui_texture()` 实现**免 import 直读加载**（即使未打开 Godot 编辑器执行 `--import`，运行时也能直接读取 PNG 字节流生成 `ImageTexture`）。

| 路径 | 尺寸 | 用途说明 |
| :--- | :--- | :--- |
| `assets/ui/icon_zan.png` | `64×64` | 【攒气】按钮图标 |
| `assets/ui/icon_bao1.png` / `bao2.png` / `bao3.png` | `64×64` | 【包子 / 双包 / 三包】连点按钮动态切换图标 |
| `assets/ui/icon_fang.png` / `strong_fang.png` | `64×64` | 【防御 / 强防】按钮图标 |
| `assets/ui/icon_xiao_yang.png` / `da_yang.png` | `64×64` | 【小羊 / 大羊】破防技图标 |
| `assets/ui/icon_ji_qi.png` / `hui_fu.png` | `64×64` | 【集气 / 回复】增益技图标 |
| `assets/ui/icon_xi_shou.png` / `bao_qi.png` / `zhong_ji.png` | `64×64` | 【吸收 / 爆气 / 终极】博弈与大招图标 |
| `assets/ui/icon_quan_jiang.png` | `64×64` | 【劝降】隐藏技图标 |
| `assets/ui/state_cd_overlay.png` | `128×64` | 技能冷却中（CD）斜纹暗色遮罩 |
| `assets/ui/state_locked_overlay.png` | `128×64` | 技能未解锁暗色边框遮罩 |
| `assets/ui/state_sealed_overlay.png` | `128×64` | 护盾被封锁（封盾）红紫交叉锁链遮罩 |
| `assets/ui/state_selected_glow.png` | `128×64` | 本回合已选中技能的金色高亮外框 |
| `assets/ui/moba_banner_bg.png` | `340×48` | 中央偏上 MOBA 反馈横幅底图 |
| `assets/ui/ticker_bg.png` | `210×92` | 右下 5 轮打字机战报底图 |
| `assets/ui/skill_ui_sheet_concept.jpg` | 原图 | AI 生成的高清卡通熊武术技能与四态 UI 概念设计大图 |
| `assets/ui/sliced_concept/concept_*.png` | `96×96` | 从 AI 概念大图切出的 16 张高清圆角图标（若喜欢插画风，可直接重命名覆盖上方 `icon_*.png`） |

> **如何切换为 AI 插画版图标**：只需将 `assets/ui/sliced_concept/concept_<name>.png` 复制并覆盖到 `assets/ui/icon_<name>.png`，无需修改任何 GDScript 代码。

---

## 3. 音频资产目录 (`assets/audio/`) 与重新生成方式

所有 21 个音频文件由 `tests/gen_sfx.py` 纯标准库生成，并通过 `BattleFx.load_wav_safe()` 支持裸 PCM WAV 免 import 加载：

* **重新生成或调参命令**：`python tests/gen_sfx.py`
* **文件列表**：
  * 开场与 BGM：`game_start.wav`, `bgm_battle.wav`
  * UI 交互：`ui_select.wav`, `ui_deny.wav`, `clap.wav`, `ding.wav`
  * 攻防与博弈反馈：`block_success.wav`（格挡成功正反馈）, `blocked_rebound.wav`（被格挡反弹受挫）, `seal.wav`（封盾锁链）, `hit.wav`, `block.wav`
  * 技能专属：`zan.wav`, `bao1.wav`, `bao2.wav`, `bao3.wav`, `strong_fang.wav`, `xiao_yang.wav`, `da_yang.wav`, `ji_qi.wav`, `xi_shou_ok.wav`, `xi_shou_fail.wav`, `bao_qi.wav`, `hui_fu.wav`, `zhong_ji.wav`, `quan_jiang.wav`
