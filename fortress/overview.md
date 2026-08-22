# 末日堡垒 · 实体与菜单图标真透明化（去棋盘格贴纸）

## 本次改动
- **根因修复**：之前的 AI 生成图把「透明背景」画成了**不透明白色/棋盘格像素**（实体精灵表 alpha 全为 255，0% 透明），导致炮塔/工厂/核心/僵尸像贴纸一样浮在地面上。
- **新管线**：采用 **solid magenta #ff00ff 背景生成 + PIL chroma-key 去背 + 右下角水印硬抹**，确保背景像素真正变为 alpha=0。
- **实体精灵表**：8 张全部重制并透明化：
  - `wall.png`：保持不透明砖石纹理（`_draw_walls` 按单元格填充需要实心）。
  - `turret_base.png`、`turret_barrel.png`、`production.png`、`core.png`、三种 `zombie_*.png`：透明背景，切片动画正常。
- **菜单图标**：16 张统一为明亮 COC 风格圆形按钮，真透明无白边、无棋盘格。
- **菜单条**：重制 `menu_bar_bg.png`，完整底部面板，修复之前被过裁/水印破坏的底边。
- **布局微调**：`fallout_menu.gd` 中 `PANEL_H` 120→128，`patch_margin` 调小，按钮不再贴底边。
- **可复用工具链**：新增 `tools/chroma_key.py`、`process_icons.py`、`process_sheets.py`，后续 AI 素材可一键去背去水印。

## 新增/替换资源
| 文件 | 说明 |
|------|------|
| `assets/sheets/*.png` | 8 张真透明实体精灵表 |
| `assets/ui/btn_*.png` | 16 张真透明圆形菜单图标 |
| `assets/ui/menu_bar_bg.png` | 新底部菜单面板 |
| `ui/fallout_menu.gd` | 菜单条尺寸/边距调整 |
| `tools/chroma_key.py` | magenta 色键 + 水印去除 |
| `tools/process_icons.py` | 16 图标批处理 |
| `tools/process_sheets.py` | 8 实体表批处理 |

## 验证结果
- `godot --headless --editor --quit --path .`：退出码 0，资源全部重新导入成功。
- `timeout 18 godot --path .`：窗口模式运行 18 秒正常，无崩溃、无脚本报错（退出码 124 为超时杀进程）。

## 待确认
- 请在 Windows 双击 `play.bat` 实测：炮塔/工厂/核心/僵尸是否还有白色方块背景，城墙是否仍无缝连接，底部菜单条是否完整不裁、按钮是否还能点击。
