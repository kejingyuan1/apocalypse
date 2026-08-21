# 末日堡垒 · 动态场景皮肤 + 相机缩放

## 本次改动
- **战场尺度**：120×120 大地图，中央 100×100 敌方基地区域。
- **动态背景皮肤**：接入 AI 生成的高质量俯视场景图，默认「末日碉堡（废墟城市）」，另有「废墟绿洲」「工业废城」两张变体；按 **B 键**循环切换。
- **相机缩放/平移**：
  - 鼠标滚轮上下：以鼠标指针为中心缩放；
  - 触屏双指捏合：缩放（InputEventMagnifyGesture）；
  - 右键拖拽：平移视角；
  - `base_zoom` 随窗口尺寸自适应，乘 `zoom_level` 后限制在 0.02–10.0。
- **BGLayer 调整**：移除程序化天空/山体/棋盘地面，改为只在 AI 背景图上绘制半透明网格线与核心光晕，保证格子可读又不遮挡美术。

## 新增资源
| 文件 | 场景 |
|------|------|
| `assets/backgrounds/bg_bunker.png` | 默认：城市废墟 + 中央碉堡 |
| `assets/backgrounds/bg_overgrown.png` | 变体：植被覆盖的废墟公园 |
| `assets/backgrounds/bg_industrial.png` | 变体：工业废城 + 毒池 |

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
- 窗口模式 `--shot` 已确认：AI 背景铺满战场、网格叠加、中央碉堡/城墙/防御塔清晰可见。

## 关键文件
- `main.gd`：新增 `bg_sprite`/`bg_paths`/`bg_index`、`_setup_background()`、`_set_background(idx)`、`_zoom_at()`、右键拖拽平移；BGLayer 改为仅绘制网格与核心光晕。
- `assets/backgrounds/`：3 张 2048×2048 高质量俯视场景图及 `.import`。
- `project.godot`：无需修改（已有窗口拉伸与最大化）。
