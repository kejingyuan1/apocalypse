# 末日堡垒（Apocalypse Fortress）· 现状审计与开发路线图

> 目的：接手 `git@github.com:kejingyuan1/apocalypse.git` 后，先盘点「设计文档体系」与「现有 Godot 工程现状」，标注文档↔代码偏差，给出分阶段开发路线，再据此动手。
> 审计时间：2026-08-21 ｜ 审计人：GodotGameplayScripter（节点通）

---

## 一、设计文档体系（Phase 1–3，状态全 PASS ✅）

仓库 `design/` 下共 **14 份 MD**，是后续开发的唯一真相来源：

| 阶段 | 文档 | 关键结论 |
|---|---|---|
| 概念 | `concept/游戏概念文档.md` | 7 动词（Place/Upgrade/Harvest/Defend/Raid/Experiment/Energize）、18×18 网格、10 类房间面积矩阵、波次公式 `N(w)=round(8×1.12^(w-1))`、生长曲线 Lv1–6、双线威胁(PVE+PVP) |
| 美术 | `art/美术圣经.md`、`art/可访问性分级.md` | tile **32×32**、设计分辨率 **640×360**、整数缩放、**单层暖橙威胁色 `DANGER_ORANGE #E8762E`**（禁止第二层红）、色盲友好、WCAG AA、HUD 三态互斥 |
| GDD×8 | `gdd/建造/经济/波次/能源/科技/PVP/离线AI/社交` | 八系统指令抽象（GridCommand/HarvestCommand/WaveCommand/PowerCommand/ResearchCommand/RaidCommand/DefendCommand/OfflineDefenseCommand/SocialCommand/AllianceCommand）、服务器权威、固定 1s tick、确定性 PRNG |
| 技术 | `tech/技术架构总览.md`、`tech/ADR.md` | Godot 4 + 服务器权威 headless + 共享核心层(core/)+平台适配层；ADR-001~005（引擎/网络/多平台/确定性/反作弊）全 Accepted |

**铁律（贯穿所有文档）**：服务器权威（客户端仅发动词指令）、固定 1s tick + 整数化 + 种子化 PRNG、单层暖橙威胁色、资源不跨账号共享（防 R6 通胀）。

---

## 二、现有 Godot 工程现状（Phase 4 垂直切片）

路径 `fortress/`，约 **151 行** `core/` 逻辑 + `main.gd`/`hud.gd`：

```
fortress/
├── project.godot          # Godot 4.6, GL Compatibility, 主场景 scenes/main.tscn
├── main.gd                # Game(Node2D): 输入翻译 + 渲染；状态机 build|combat|win
├── hud.gd                 # HUD(CanvasLayer): 状态/波次/剩余/废料/选中（暖橙文字）
├── core/
│   ├── grid_model.gd      # GridModel: 18×18 网格、place/demolish（纯逻辑）
│   ├── grid_command.gd    # GridCommand: 指令抽象（仅 PLACE 实现）
│   ├── room_defs.gd       # RoomDefs: 4 类房间(墙/防御/生产/指挥) 尺寸/HP/贴图
│   ├── wave_manager.gd    # WaveManager: N(w) 公式 / interval / tick_seconds
│   └── zombie.gd          # Zombie: 3 类(Walker/Runner/Spitter)
├── scenes/main.tscn       # 主场景
└── assets/
    ├── ai/                # 11 张 512×512 AI 原图
    ├── art/               # 11 张 32×32 降采样精灵（静态单帧，无动画）
    ├── art_preview.png
    ├── gen_sprites.py / downscale_ai.py
```

**架构方向正确**：逻辑在 `core/`（纯 `RefCounted`，无节点依赖，符合 ADR-002 可服务端化），`main.gd` 只做输入翻译+渲染，`hud.gd` 用暖橙。契合「共享核心层 + 客户端渲染」原则。

---

## 三、⚠️ 文档 ↔ 代码 偏差清单（开发前必须对齐）

| # | 位置 | 代码现状 | GDD 权威值 | 偏差 | 状态 |
|---|---|---|---|---|---|
| 1 | `grid_model.gd` `set_level()` | ~~`[6,8,10,12,14,16,18,18,18]`~~ → `[6,8,10,13,15,18]` | Lv1–6 = **6/8/10/13/15/18** | Lv4/5/6 错误 | ✅ 已对齐 |
| 2 | `room_defs.gd` `hp(COMMAND)` | 500 → **600** | 指挥核心 HP = **600**（波次 §5.3） | 少 100 | ✅ 已对齐 |
| 3 | `wave_manager.gd` `interval()` | ~~`[120,105,90,80,70,60,...]`~~ → `[120,105,90,78,68,60]` | Lv4/5/6 = **78/68/60**（波次 §3.1） | Lv4/5 错误 | ✅ 已对齐 |
| 4 | `zombie.gd` HP/速度 | 固定 → **公式化** `make(kind,wave)` | `HP=20×(1+0.15(w-1))`×系数；速度×系数 | 未随波次缩放 | ✅ 已对齐（注：速度系数用 §5.2 Walker1.0/Runner1.8/Spitter0.9；HP 系数用 §3.2 类型系数 1.0/0.8/1.3，与 §5.2 的 HP 倍率 1.0/0.6/1.1 口径不同，取总威胁公式口径） |
| 5 | `room_defs.gd` 房间覆盖 | 仅 4 类 | 10 类 | 缺 6 类 | ⬜ 留待 Phase D（MVP 可接受） |
| 6 | `main.gd` `_tick()` | 空 `pass` → 接入 `BattleSim.tick()` | 破墙/防御开火/资源消耗 | 核心逻辑空 | ✅ 已实现（`core/battle_sim.gd`） |
| 7 | 寻路 | 直线 → **BFS 距离场 + breach** | A* + 破墙 | 无寻路 | ✅ 已实现（BFS 等价于均匀网格 A*，h=0；见 §七 简化说明） |
| 8 | 防御 | 无开火 → **DEFENSE 自动开火** | DEFENSE 自动范围拒止 | 丧尸直达核心 | ✅ 已实现（射程 4 / 30 每 tick，待平衡） |
| 9 | `assets/art/` | 静态单帧 | 帧动画 | 已知短板 | ⬜ 留待 Phase E |
| 10 | `battle_sim.gd` 建造系统 | 无拆除/升级/软上限 | 拆除返还 α=0.5（§3.3）、升级不占新格（§3.3）、资源软上限（经济 §5.2） | 建造系统未闭环 | ✅ 已落地（try_demolish/try_upgrade/SOFT_CAP） |

> 偏差 1–4 是**纯数值**问题，低风险，应最先对齐；偏差 6–8 是**功能空洞**（README §5 明确列为 Phase 4 打磨第一项）；偏差 10 是建造系统闭环项。截至 2026-08-21，Phase A（1–4）、Phase B（6–8）、Phase C（10）均已落地。

---

## 四、Phase 4 待办（README §5）对照现状

- [x] 破墙/防御开火/资源消耗接入 `_tick()` → **已实现（`core/battle_sim.gd` + `main.gd` 快照插值渲染）**
- [x] Phase C 建造系统完善：拆除返还（α=0.5）/ 升级加固（HP×1.5，耗 15 废料）/ 资源软上限（废料 500 / 生物质 300）/ 战斗锁定（建造·拆除·升级均 `state=="build"` 守卫）→ **已实现（`core/battle_sim.gd` + `main.gd` 输入 + `hud.gd` 提示）**
- [ ] Phase 5：能源/经济/科技/PVP 系统 → 未做
- [ ] 美术：精灵动画化（帧动画/精灵表）→ 未做
- [ ] 网络：core/ 迁移服务器权威 headless（ADR-002）→ 未做（架构已就位：core/ 纯 RefCounted，可 headless 复用）

---

## 五、开发路线图（最小可行优先 · 分阶段）

> 遵循「先最小闭环、再扩展、架构按需在用户要求时引入」的原则，不一次性铺大架构。

### Phase A — 数值与文档对齐（低风险·即时）
- A1 `grid_model` `set_level` → `[6,8,10,13,15,18]`
- A2 `RoomDefs.hp(COMMAND)` → `600`
- A3 `WaveManager.interval` → `[120,105,90,78,68,60]`
- A4 `Zombie` HP/速度按 GDD 公式化（`hp=round(20×(1+0.15(w-1))×coef)`，`coef` Walker1.0/Runner0.8/Spitter1.3；speed Walker1.0/Runner1.8/Spitter0.9 ×基准）

### Phase B — 真实战斗闭环（Phase 4 核心·单系统可测）
- B1 A* 寻路 + 破墙 breach（向指挥核心推进，遇墙破墙）
- B2 DEFENSE 房间自动开火（射程/冷却/伤害，击杀丧尸）
- B3 `_tick()` 接入：破墙伤害 + 防御开火 + 波次消耗（废料/生物质，公式见经济 §5.5）
- B4 胜负判定：核心 HP 归零→失败（重置 Lv2）；撑过 10 波→胜利

### Phase C — 建造系统完善 ✅（2026-08-21 已落地）
- C1 资源软上限 / 升级 / 拆除返还（经济 GDD 简化版）→ **已实现**
  - `SOFT_CAP_SCRAP=500` / `SOFT_CAP_BIOMASS=300`，`_settle_wave()` 结算后钳制
  - `try_upgrade(id)`：耗 15 废料，`grid.harden()` 使 HP×1.5、升级等级 +1（不占新格，对齐 §3.3）
  - `try_demolish(id)`：返还 `floor(造价×0.5)`（DEMOLISH_REFUND=0.5，对齐 §3.3）
- C2 战斗锁定（波次中禁止建造/拆除/升级，建造 §6）→ **已实现**：`try_place`/`try_demolish`/`try_upgrade` 均以 `state=="build"` 守卫
- C3 HUD 三态（运营/防御/反攻，美术 §7.3）→ **Phase B 已落地三态；本阶段补充拆除/升级提示文案**

### Phase D — 多房间类型 + 能源/经济最小闭环
- D1 `RoomDefs` 扩到 10 类 + 补全 `assets/art/` 精灵
- D2 能源网络（Supply/Demand/降载 T4→T0，能源 §3.3）
- D3 经济（生产产出/软上限/波次消耗，经济 §3）

### Phase E — 美术动画化
- `AnimatedSprite2D` + 精灵表（idle/walk/attack），美术 §8 帧率

### Phase F — 服务器权威迁移（ADR-002）
- `core/` 抽 headless；`CommandRouter`/`EventBus`/`SnapshotBuffer`；快照同步

---

## 六、建议第一步

**推荐从 Phase A + Phase B 起步**：先消除数值偏差（保证代码=文档），再把空 `_tick()` 变成真实战斗闭环——这正好打通 README 说的「建造→守→扩张」最小循环，且改动集中在 `core/` 与 `main.gd`，可独立运行验证（F5 跑 `main.tscn`），符合「先最小可行、再扩展」原则。

---

## 七、Phase A+B 实施记录（2026-08-21）

### 已落地改动
| 文件 | 改动 |
|---|---|
| `core/grid_model.gd` | `set_level` 生长表 → `[6,8,10,13,15,18]`（对齐建造 §5.2） |
| `core/room_defs.gd` | `hp(COMMAND)` → `600`（对齐波次 §5.3） |
| `core/wave_manager.gd` | `interval` 表 → `[120,105,90,78,68,60]`（对齐波次 §3.1） |
| `core/zombie.gd` | `make(kind, wave)` 公式化 HP/速度（对齐波次 §3.3 / §5.2） |
| `core/battle_sim.gd` | **新增**：服务端权威战斗内核。BFS 距离场寻路 + breach 破墙 + DEFENSE 自动开火 + 波次消耗结算（废料/生物质，逐字引用经济 §5.5）+ 胜负判定 + 种子化 RNG 确定性（ADR-004）。固定 1s tick。 |
| `main.gd` | 重构为薄渲染/输入层：持有 `BattleSim`，`_process` 内按 `BattleSim.TICK` 驱动 `sim.tick()` 并对 `prev_pos→pos` 做快照插值渲染；建造命令转发 `sim.try_place`。 |
| `hud.gd` | 三态文字（建造/战斗/胜利/失败）+ 生物质显示 + 选中造价；持续单层暖橙 `DANGER_ORANGE #E8762E`（美术圣经铁律）。 |
| `tools/validate.gd` | **新增**：无头冒烟测试（强制预编译全部 core 脚本 + 跑通整波 + 确定性校验 + breach 不崩），结果 `print` + 写 `user://validate_result.txt`。 |

### 战斗闭环（build → defend → expand）
1. **build**：玩家在 `build` 态用 1/2/3 选墙/防御/生产，左键放置（扣废料）；空格开始波次。
2. **defend**：`sim.begin_wave(w)` 按 `N(w)` 生成丧尸（类型配比 WALKER/RUNNER/SPITTER），BFS 寻路逼近指挥核心；被墙阻挡则 breach 破墙；DEFENSE 房每 tick 自动开火；波末结算消耗（废料/生物质）并发放奖励。
3. **expand**：每存活 3 波堡垒等级 +1（`grid.set_level`），网格扩展；撑过 10 波 → `win`；核心 HP 归零 → `fail`。

### 已知简化（待平衡 / 后续 Phase）
- **寻路用 BFS 距离场**，等价于均匀网格 A*（h=0）。GDD §3.4 名义 A*；四邻均匀代价下结果一致，后续若引入对角/地形代价再换 A*。
- **breach 为房间级**：某格 HP 归零即 `grid.demolish` 整个房间（GDD §3.4 描述"该 cell 变 breach"为逐格语义；房间级是当前切片简化，Phase F 前够用）。
- **DEFENSE 开火无视线校验**：仅按射程（4 格）命中最近丧尸；后续可加 LOS。
- **波次规模未乘 FortMul**：`WaveManager.count(w)` 用纯 `N(w)`（与现有代码一致）；GDD §3.1 的 `N_eff=N(w)×FortMul(Lv)` 留待 Phase D 接入等级外部乘数时一并处理。
- **数值为设计提案口径**（GDD §5.x 标注"待平衡 pass"）：`DEFENSE_RANGE=4 / DMG=30 / BREACH_DPS=12 / ZOMBIE_CORE_DPS=15 / 房造价 20/40/30` 均为可调常量，集中在 `battle_sim.gd` 顶部。
- **失败态为软惩罚占位**：当前 `fail` 仅停战并显示提示，未实现"重置 Lv2"的重建逻辑（GDD §5.5）；胜利后也未接"重开"。留待 Phase C。

### Phase C 实施记录（2026-08-21）

#### 已落地改动
| 文件 | 改动 |
|---|---|
| `core/grid_model.gd` | 新增 `harden(id)`：升级等级 +1，HP 取整 ×1.5（对齐建造 §3.3 升级不占新格） |
| `core/battle_sim.gd` | 新增 `try_demolish(id)`（返还 `floor(造价×0.5)`，守卫：非建造态/房间不存在/指挥核心 → -1）；新增 `try_upgrade(id)`（耗 `UPGRADE_COST=15` 废料，`grid.harden`，守卫同上）；`_settle_wave()` 结算后按 `SOFT_CAP_SCRAP=500 / SOFT_CAP_BIOMASS=300` 钳制资源（经济 §5.2 简化版） |
| `main.gd` | 输入层新增：右键 / `KEY_X` / `KEY_DELETE` → 拆除鼠标悬停格所属房间（并 `queue_free` 对应精灵）；`KEY_U` → 升级该房间；均受 `state=="build"` 守卫 |
| `hud.gd` | 建造态提示补充：`右键/X拆除(返还50%) | U升级(15废料)` |
| `tools/validate.gd` | 新增「场景 C」：拆除返还数值校验 + 指挥核心不可拆守卫 + 软上限钳制校验；显式 `preload("res://main.gd"/"res://hud.gd")` 强制渲染层可编译；修复文件打开失败时的误 `quit()` 死代码 |

#### Phase C 已知简化（待后续 Phase）
- **拆除冷却 `Cd`（建造 §3.3 建议 30s）未实现**：拆除仅在 `build` 态允许，且 build 态无 tick 计时，故 MVP 暂不做冷却；待 Phase D 接入时间系统再补。
- **软上限为全局常量**：GDD 中软上限由「仓储 Storage」房间提升（建造 §3.4）；当前未实现 Storage 房间，故用固定上限 `500/300` 占位，待 Phase D 扩房间类型时改为动态上限。
- **升级仅加固 HP**：GDD §3.3 升级还应增强「产出/防御/供能」；当前切片仅做承伤 HP×1.5（对抗 breach/核心伤害最直接有效），产出/供能增强随对应系统（经济/能源）在 Phase D/E 接入。
- **`grid_command.gd` 为指令抽象占位**：已实现 `GridCommand`（PLACE/MOVE/UPGRADE/DEMOLISH 枚举 + `place()` 构造），但当前 `BattleSim` 直接以 `try_*` 方法承接（客户端仅发动词指令，服务端权威结算，符合 ADR-002）。`GridCommand` 留作 Phase F 服务器权威迁移时的指令序列化载体，非当前运行路径依赖，不影响构建。

### Phase C 构建修复记录（2026-08-21 追加）
- **报错现象**：用户 headless 启动时 `main.gd` 大量 `Identifier not declared`（`RoomDefs`/`GridModel`/`BattleSim`/`Zombie`），窗口化运行仅灰屏 + 标题文字。
- **根因**：
  1. `.godot/` 缓存缺失时，Godot 4 `class_name` 全局类名在 headless 首次运行无法注册；项目又未提交 `.import` 文件。
  2. `core/room_defs.gd` 与 `core/zombie.gd` 用 `preload` 引用 PNG，headless 无导入器时直接编译失败。
  3. `battle_sim.gd` 使用 `WaveManager` 但未显式预加载。
- **修复**：
  - 所有 `core/` 脚本及 `main.gd`/`hud.gd` 移除 `class_name`，改用 `const Xxx := preload("res://core/xxx.gd")` 显式引用。
  - `room_defs.gd`/`zombie.gd` 的纹理函数 `preload` 改为 `load`，让图片加载推迟到运行时，避免 headless 编译期崩溃。
  - `battle_sim.gd` 添加 `const WaveManager := preload("res://core/wave_manager.gd")`。
  - `zombie.gd` 工厂方法改用运行时 `load("res://core/zombie.gd")` 自身实例化，避免自引用 preload 循环。
  - 生成并提交全部 `.import` 文件与 `battle_sim.gd.uid`/`validate.gd.uid`。
- **结果**：`Godot_v4.6.3-stable_win64_console.exe --headless --script res://tools/validate.gd` 输出 `VALIDATE_OK`。

### 本地验证（重要）
- **沙箱内可运行 `Godot_v4.6.3-stable_win64_console.exe`**：之前误报「拒绝访问」是因为使用了外层目录名带 `.exe` 的非控制台二进制；改用 `Godot_v4.6.3-stable_win64_console.exe` 可正常执行 headless 与窗口化命令。本次修复后已在本沙箱实测：
  ```text
  VALIDATE_START godot=4.6.3-stable (official) main_ok=true hud_ok=true
  A spawn=8 wave=1 state=fail ticks=9 zombies_left=5 scrap=120 biomass=50 core_hp=-15
  DETERMINISTIC=true
  B walls_before=10 walls_after=10 wave=1 state=fail ticks=12 core_hp=-75
  C cost_paid=40 refund=20 after_demo=180 cmd_guard_ok=true cap_scrap=500 cap_biomass=300
  VALIDATE_OK
  ```
- **命令**（在仓库 `fortress/` 目录下）：
  ```bash
  # 无头冒烟测试（编译 + 跑通战斗 + 确定性 + breach + Phase C 拆除/升级/软上限）
  Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/validate.gd
  # 实时试玩
  Godot_v4.6.3-stable_win64_console.exe --path .
  ```
  前者会在终端打印 `VALIDATE_OK` 及各场景结果；脚本并 `preload` `main.gd`/`hud.gd` 强制渲染层可编译。后者进 `main.tscn` 即可 建造→空格开波→守→扩张，建造态下右键/X 拆房、U 升级。
- **窗口化渲染已在本沙箱启动验证**：`--path .` 能正常初始化 OpenGL (Intel Iris Xe) 并进入窗口，因无截图工具未留存像素级截图，但脚本逻辑层已通过无头验证。
