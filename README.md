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
- 全部精灵由 `assets/gen_sprites.py`（Python PIL）按**美术圣经调色板**生成，32×32，可复现。
- 已生成：地面/城墙/防御/生产/指挥 房间图，Walker/Runner/Spitter 丧尸图，威胁⚠/能源/晶体 图标。
- 预览见 `assets/sprites_preview.png`。
- 注：当前为**程序化占位像素图**，正式发行前由美术（art-director）产出高保真手绘像素集替换同名文件即可，路径不变。

---

## 5. 下一步
- [ ] Phase 4 打磨：破墙/防御开火/资源消耗接入 `_tick()`（逻辑已在 GDD 定义）
- [ ] Phase 5 制作：按冲刺实现 能源/经济/科技/PVP 系统
- [ ] 美术：手绘像素集替换占位图、动画帧、特效
- [ ] 网络：core/ 逻辑迁移到服务器权威 headless 服务（ADR-002）
