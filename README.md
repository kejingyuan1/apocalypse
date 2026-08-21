# 末日堡垒 · Apocalypse Fortress

> 像素风 · 末日堡垒策略/建造游戏（PC + 移动 + Web，实时联网 PVP，服务器权威）
> 本仓库包含：**完整设计文档（Phase 1–3）** + **Phase 4 可运行垂直切片（Godot 工程）** + **像素美术资产**。

---

## 1. 怎么在另一台电脑接手

```bash
git clone git@github.com:kejingyuan1/apocalypse.git
cd apocalypse
```

### 打开游戏工程
1. 安装 **Godot 4.6.x**（本机路径示例：`D:/GODOT/Godot_v4.6.3-stable_win64.exe`）。
2. 用 Godot 打开 `fortress/project.godot`（导入后会生成 `.godot/` 缓存，已被 .gitignore 忽略）。
3. F5 运行 `scenes/main.tscn` 即可看到「建造 + 波次」最小闭环原型。

### 操作
- **左键**：在网格上放置选中房间
- **1 / 2 / 3**：切换 城墙 / 防御 / 生产
- **空格**：开始下一波（共 10 波，撑过即胜利）

---

## 2. 目录结构

```
apocalypse/
├── README.md                 # 本文件
├── design/                   # 设计文档（Phase 1–3，全部门控 PASS）
│   ├── concept/游戏概念文档.md
│   ├── art/美术圣经.md
│   ├── art/可访问性分级.md
│   ├── gdd/                  # 8 份系统 GDD
│   │   ├── 建造系统.md
│   │   ├── 实时PVP对战系统.md
│   │   ├── 经济系统.md
│   │   ├── 波次系统.md
│   │   ├── 能源网络系统.md
│   │   ├── 科技实验系统.md
│   │   ├── 离线防御AI.md
│   │   └── 社交联盟系统.md
│   └── tech/
│       ├── 技术架构总览.md
│       └── ADR.md            # 5 条架构决策记录
└── fortress/                 # Phase 4 Godot 工程（垂直切片）
    ├── project.godot
    ├── main.gd               # 主场景脚本（输入翻译 + 渲染）
    ├── hud.gd                # HUD（暖橙威胁色）
    ├── core/                 # 纯逻辑层（可服务端化，无节点依赖）
    │   ├── grid_model.gd     # 网格模型 + 生长曲线
    │   ├── grid_command.gd   # GridCommand 指令抽象
    │   ├── room_defs.gd      # 房间类型/面积/HP/精灵
    │   ├── wave_manager.gd   # 波次公式 N(w)=round(8*1.12^(w-1))
    │   └── zombie.gd         # 丧尸实体（Walker/Runner/Spitter）
    ├── scenes/main.tscn
    └── assets/
        ├── gen_sprites.py    # 像素美术生成脚本（PIL，可复现）
        ├── sprites/          # 11 张 32×32 像素精灵（PNG）
        └── sprites_preview.png  # 放大预览拼接图
```

---

## 3. 设计文档索引

| 阶段 | 产物 | 状态 |
|---|---|---|
| Phase 1 | 游戏概念文档、美术圣经 | PASS |
| Phase 2 | 8 份系统 GDD（建造/PVP/经济/波次/能源/科技/离线AI/社交） | 全 PASS |
| Phase 3 | 技术架构总览 + 5 条 ADR + 可访问性分级 | PASS |
| Phase 4 | Godot 垂直切片（建造+波次）+ 像素美术 | 进行中 |

### 核心设计铁律（务必遵守）
- **服务器权威**：客户端只发动词指令（GridCommand…），所有结算以服务端为准。
- **固定 1s tick + 确定性**：经济/能源/波次/离线 AI 同源 tick，`seed=hash(...)` 驱动 PRNG。
- **单层暖橙威胁色**：唯一威胁色 `DANGER_ORANGE #E8762E`，红绿不得作唯一区分，**禁止第二层红色 UI**。
- **资源不跨账号共享**：废料/晶体/生物质 单账号归属，社交层不得提供可掠夺的三资源转移通道（防通胀 R6）。

### 风险登记表（R 编号）
跨文档连续编号，每条均含缓解方案（详见各 GDD）：
- R6 经济失衡｜R11 电网级联崩溃｜R16 科技雪球｜R20 确定性回放歧义｜R25 集结 farm 通胀｜R26 联盟仓库变转移通道｜R-B 作弊
- 完整清单：R5 → R29（设计/经济/波次/能源/科技/离线AI/社交）+ R-A 系列（可访问性）+ R-A/B/E/F/H（架构）

---

## 4. 像素美术资产
- **当前为 AI 生成的像素风美术**（ImageGen 工具产出 512×512 原图，再由 `assets/downscale_ai.py` 降采样为 32×32 游戏精灵）。
- 原图（高分辨率源）：`assets/ai/<name>/*.png`（11 张，512×512，可二次加工）。
- 游戏精灵：`assets/art/*.png`（11 张，32×32，Lanczos 降采样 + 自适应调色板量化，保留硬边与识别度）。
  - 地面 `tile_ground` / 城墙 `tile_wall` / 防御 `room_defense` / 生产 `room_production` / 指挥 `room_command`
  - 丧尸 `zombie_walker` / `zombie_runner` / `zombie_spitter`
  - 图标 `icon_threat`（威胁⚠）/ `icon_energy`（能源）/ `icon_crystal`（晶体）
- 游戏代码精灵引用集中在 `core/room_defs.gd`、`core/zombie.gd`（9 处 `preload("res://assets/art/...")`），新增精灵只需放 `assets/art/` 并改对应 preload。
- 预览拼接图（4× 放大）：`assets/art_preview.png`。
- ⚠️ **已知短板：当前精灵是静态单帧图，无动画。** 动图/帧动画列为后续待办（见 §5）。
- 历史占位图：`assets/sprites/`（早期 PIL 程序化方块图，已被 `assets/art/` 取代，已移出版本库，仅本地残留）。

---

## 5. 下一步
- [ ] Phase 4 打磨：破墙/防御开火/资源消耗接入 `_tick()`（逻辑已在 GDD 定义）
- [ ] Phase 5 制作：按冲刺实现 能源/经济/科技/PVP 系统
- [ ] **美术：精灵动画化（重点待办）** —— 当前 `assets/art/*.png` 均为**静态单帧图，不会动**。需产出类 GIF/APNG 的帧动画或精灵表（sprite sheet），覆盖 idle / walk / attack 等状态：
  - 丧尸 Walker/Runner/Spitter：行走循环帧、攻击帧
  - 房间 防御/生产/指挥：idle 微动、被击/开火特效帧
  - 图标 威胁/能源/晶体：脉冲/流动循环帧
  - 实现方式：`AnimatedSprite2D` + 精灵表，或 `assets/downscale_ai.py` 扩展为批量降采样多帧
- [ ] 美术：动画帧接入后，补充命中特效、波次预警动效
- [ ] 网络：core/ 逻辑迁移到服务器权威 headless 服务（ADR-002）
