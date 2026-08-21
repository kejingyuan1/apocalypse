# 末日堡垒 · 彩绘大地图 + 入场运镜

## 本次改动
- **背景风格重做**：由写实城市废墟替换为「手绘彩绘战术地图」——整张地图像摊开的桌游版图，中央是平整战场空地，四周是山脉、河流、森林、罗盘、装饰边框。房间/城墙/部队像摆在沙盘上的棋子，视觉尺度协调。
- **3 套动态皮肤**：默认「末日碉堡」+ 变体「森林战场」「废土沙漠」；按 **B 键**循环切换。
- **网格稀疏化**：每 5 格一条淡线，只在边界/中线稍亮，不再密集成工程纸压过地图细节。
- **镜头由远及近开场运镜**：启动后相机从远景（zoom = base_zoom × 0.55）用 Cubic Ease-Out 在 2 秒内慢慢拉近到战场；用户滚动/拖拽/下兵会立刻中断动画。
- **保留交互**：鼠标滚轮以指针为中心缩放、触屏双指捏合缩放、右键拖拽平移。

## 新增/替换资源
| 文件 | 场景 |
|------|------|
| `assets/backgrounds/bg_bunker.png` | 默认：彩绘山地/河流/罗盘，中央平地 |
| `assets/backgrounds/bg_forest.png` | 变体：森林/湖泊/花环边框，中央营地 |
| `assets/backgrounds/bg_wasteland.png` | 变体：沙漠/遗迹/仙人掌/干河床 |

> 注：AI 生成图右下角带有平台「AI生成」水印；当前接口无参数可彻底去除。如需无水印版本，可换用本地 SD / Midjourney 输出同名文件覆盖。

## 验证结果
```
VALIDATE_START godot=4.6.3-stable (official) main_ok=true hud_ok=true
A grid=120 core=1 walls=224 defense=8 prod=4 army=58
A deployed=58 army_left=0 state=combat
A end state=win ticks=208 core_hp=-1 units_left=30
B end state=fail ticks=107 (期望 fail：兵尽)
C total_shots=137 fire_ok=true
VALIDATE_OK
```
- 窗口模式 `--shot` 已确认：彩绘地图铺满战场、稀疏网格可读、中央碉堡/城墙/部队清晰可见。

## 关键文件
- `main.gd`：
  - 替换 `bg_paths` 为 3 张彩绘地图；`_setup_background()` / `_set_background()` 不变。
  - 新增 `_intro_camera()` 开场推镜、`_cancel_intro()` 用户交互中断。
  - 调整 BGLayer 网格：每 5 格一条淡线，仅边界/中线加重。
  - 保留 `_zoom_at()`、右键拖拽平移与 `--shot` 开发截图分支。
- `assets/backgrounds/`：3 张 2048×2048 彩绘大地图及 `.import`。
- `project.godot`：无需修改（已有窗口拉伸与最大化）。
