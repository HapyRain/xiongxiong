# 《拍拍熊熊》v3 (1080P 全屏三渲二特效 · 炉石烧绳锚点 · 街机双层技能盘) 零漂移交接规范

> **定位与强约束说明**：本文件是《拍拍熊熊》v3 视听与 UI 系统的唯一权威交接契约。本地 Agent 在接手维护或微调时，**必须严格遵守下方「八条铁律（Zero-Drift Guardrails）」**，严禁自行发挥、严禁退回旧版 390×820 低清布局或无描边灰块按钮。

---

## 一、 本地 Agent 必读：八条零漂移铁律（Zero-Drift Guardrails）

1. **分辨率铁律（1080×1920 竖版 1080P）**：
   * `project.godot` 的设计视口分辨率固定为 `viewport_width=1080`、`viewport_height=1920`（桌面端调试窗口缩放预览 `window_width_override=540`、`window_height_override=960`）。
   * **禁止**将视口改回 `390×820`，所有字体、线宽、粒子半径均按 1080P 规格定义。
2. **严禁使用常量名 `UiTheme.OK`（防全局遮蔽）**：
   * 在 `scripts/ui/ui_theme.gd` 中成功绿常量必须命名为 **`OK_GREEN`**，**严禁**定义为 `const OK`，否则会遮蔽 Godot 全局枚举 `Error.OK` 导致编译报错。
3. **技能栏图文分离与粗黑描边铁律（严禁图标垫在文字正下方）**：
   * 在 `UiTheme.make_skill_slot()` 中，技能图标 `IconTex` 必须固定锚定在**按钮左侧独立区域**（`anchor_left=0, offset_left=8..12`），**严禁**使用 `PRESET_FULL_RECT` 铺满按钮中心垫在文字底下。
   * 按钮主文案（严格 2 个汉字 `GameRules.action_short_name(act)`）必须设置纯白字色 `#FFFFFF` + **`8~10px` 纯黑漫画描边 (`outline_size = 8..10, font_outline_color = #090D17`)**。
4. **严禁在技能按钮上使用 Emoji（`🔒 / ⏳ / 🚫` 全面禁用）**：
   * 技能槽底部状态统一由深色半透明底栏 `SubBar/SubBadge` 承载，文案只准用纯中文与数字：`1分解锁`..`8分解锁`、`冷却 2`、`护盾被封`、`缺气(2)`、`耗 1 盾`、`+1气 +1盾`、`连点1~3连`。
5. **严禁结算期间整盘技能按钮闪烁变灰**：
   * 在 `UiTheme.update_skill_slot()` 中，必须严格区分 `usable = s.can_use_action(who, act)`（技能本身是否解锁/够气/无CD）与 `can_lock`（当前是否处于选招时间窗）。
   * 当 `usable == true` 且 `can_lock == false`（即 0.8s 亮招结算动画期间），按钮虽然 `disabled = true` 拦截点击，但其 `disabled` 样式盒**必须保持与 `normal` 相同的鲜亮彩色样式**，只有 `usable == false` 的技能才显示深岩灰底色 (`DISABLED_BG`)。
6. **全屏三渲二特效舞台 (`CelStageCanvas`) 边界铁律**：
   * `BattleFx.CelStageCanvas` 挂载于 `FxLayer` 下，利用 `_draw()` 渲染全屏漫画放射速度线、Impact Frame 顿帧闪光、六边金青折射护盾波、吸收引力黑洞涡旋与粗黑描边刀光。
   * 特效绘制高度限制在上方舞台区（`y = 0 .. 1320`），**绝不遮挡底部技能操作盘**。
7. **消灭重复文字与重叠胶囊飘字铁律**：
   * 角色状态栏（HUD）左侧放置三渲二熊头像 (`avatar_bear_me.png` / `avatar_bear_opp.png`)，血槽与盾槽并排紧凑展示，数值标签（`me_hp / me_qi / me_shield`）只写纯比值 `"3/4"`，**严禁**写成 `"血 ... 血 3/4"`。
   * 回合结算时，**只保留正中偏上 `MobaBanner` + 舞台中央三渲二漫画拟声大字 (`_spawn_comic_callout`) + 右下角微缩打字机记招器 (`BattleTicker`)**，严禁在上下 HUD 卡牌上再叠黑底胶囊飘字。
8. **音频 100% 必响三保险机制（严禁开启 QOA 压缩）**：
   * `assets/audio/*.wav.import` 必须保持 `compress/mode=0`（无损 16-bit PCM），**严禁**设为 `compress/mode=2`（QOA 压缩会破坏 `bgm_battle.wav` 的循环点 `loop_end`）。
   * `BattleFx.load_wav_safe()` 优先通过 `FileAccess.get_file_as_bytes()` 直接构造未压缩 `FORMAT_16_BITS` 的 `AudioStreamWAV`，并内置 `_synth_fallback_wav()` 内存级 PCM 合成器兜底。

---

## 二、 1080×1920 竖屏纵向分区坐标表

| 纵向区间 (`y`) | 区域名称 | 关键节点名 | 视觉与交互说明 |
| :--- | :--- | :--- | :--- |
| `0 .. 1920` (底层) | **三渲二夕阳天台舞台背景** | `StageBgTex`, `StageTint` | `assets/ui/stage_bg_cel.png` 全屏铺底 + `0.18` 暗角衬托前景 |
| `20 .. 88` | **顶部比分与菜单栏** | `InfoLabel`, `MenuBtn` | 30px 粗黑描边白字显示回合与比分；右上唯一「菜单」按钮（已隐藏 `QualitySettings` 常驻浮动齿轮） |
| `96 .. 224` | **对手街机状态栏 (HUD)** | `OppHudCard` / `_you_panel` | 左侧赤焰熊头像 `avatar_bear_opp.png` + 右侧血槽/盾槽同排 + 元气槽 |
| `236 .. 348` | **MOBA 居中偏上博弈横幅** | `MobaBanner` | 宽 `920×112`，展示格挡成功/被挡/破防封盾/吸收得手/劝降等主反馈 |
| `348 .. 1060` | **全屏三渲二交锋舞台区** | `CelStageCanvas`, `MeDuelCard`, `OppDuelCard` | 双侧三渲二亮招卡 (`340×168`) + 全屏放射速度线 + 六边圣盾特写 (`vfx_shield_cutin.png`) + 黑洞特写 (`vfx_vortex_cutin.png`) + 漫画拟声大字 |
| `1060 .. 1208` (靠右) | **右下贴边微缩打字机记招器** | `BattleTicker` | 宽 `400×148`，靠右对齐 (`ALIGNMENT_END`)，半透明磨砂暗底 (`alpha=0.62`)，最多留 5 行，结算后从下往上推并打字机逐字显形 |
| `1218 .. 1280` | **炉石式烧绳子 + 拍点锚点** | `BurningRopeBar` | 横贯全屏 (`1020×62`)，内嵌 `一拍`、`二拍`、`封盘` 三枚立体锚点与旋转燃烧火花头 `RopeSpark` (`rope_spark.png`) |
| `1292 .. 1420` | **我方街机状态栏 (HUD)** | `MeHudCard` / `_me_panel` | 左侧金罡熊头像 `avatar_bear_me.png` + 右侧血槽/盾槽 + 元气槽 |
| `1432 .. 1668` | **进阶技能战术盘 (4×2)** | `SkillGrid` (`Action5..12`) | 每格高 `112px`，左图标 + 居中 34px 黑边白字 + 右上耗气胶囊 + 底部黑底状态条 |
| `1680 .. 1832` | **黄金拇指三大主键** | `PrimaryRow` (`Action4,0,1`) | 每键高 `152px`，【防御】【攒气】【包子（连点升阶单包/双包/三包）】 |

---

## 三、 UI 与特效贴图资产清单 (`assets/ui/`)

| 文件名 | 规格 | 用途说明 |
| :--- | :--- | :--- |
| `stage_bg_cel.png` | `1080×1920` | 竖屏 1080P 三渲二夕阳校园天台对决舞台背景（含漫画集中线与中央法阵） |
| `avatar_bear_me.png` | `220×128` | 我方「金罡武道熊」三渲二头像徽章 |
| `avatar_bear_opp.png` | `220×128` | 对手「赤焰狂暴熊」三渲二头像徽章 |
| `vfx_shield_cutin.png` | `360×220` | 格挡成功 / 强防弹反时的三渲二天青六边圣盾爆裂特写卡 |
| `vfx_vortex_cutin.png` | `360×220` | 吸收技能触发时的三渲二紫黑引力黑洞闪电特写卡 |
| `rope_spark.png` | `96×96` | 炉石式烧绳倒计时导火索前端旋转燃烧火花贴图 |
| `icon_*.png` (14 张) | `128×128` | 14 个动作的高对比三渲二粗黑描边技能徽章（置于按钮左侧独立槽） |
| `state_locked_overlay.png` | `256×128` | 未解锁状态暗斜纹边框遮罩（中心留空，不挡字） |
| `state_cd_overlay.png` | `256×128` | 冷却中状态冰蓝斜纹边框遮罩（中心留空，不挡字） |
| `state_sealed_overlay.png` | `256×128` | 封盾状态四角紫红锁链遮罩（中心留空，不挡字） |
| `state_selected_glow.png` | `256×128` | 已锁定技能的亮金双层漫画发光外框 |

---

## 四、 本地验证与回归自检命令

在 Windows 终端项目根目录下运行：
```powershell
# 1. 重新生成并峰值归一化全套 21 个 WAV 音效与 BGM（可选，工程内已预生成）
python tests/gen_sfx.py

# 2. 运行 Python 规则全矩阵回归（123 项断言）
python tests/test_rules_v2.py

# 3. 运行 Godot 4.7.2 全量 8 项 headless 自检（含 1080x1920 视口、双层 11 键、2 字硬约束、CelStageCanvas、BurningRopeBar）
.\tools\run_checks.ps1
```
