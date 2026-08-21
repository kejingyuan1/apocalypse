# 末日堡垒 · COC 式进攻玩法重构

## 本次改动
- **玩法翻转**：从「玩家守城 + 山洞刷怪」改为 **COC 式进攻**：玩家从地图任意空白格下兵，攻打敌方基地。
- **敌方基地**：20×20 网格中央自动生成核心（2×2）+ COC 式城墙闭环 + 4 座防御塔 + 2 座生产房。
- **部队**：初始 58 人口（突击兵 36 / 突袭兵 14 / 喷吐者 8）。左键点击空地部署，1/2/3 切换兵种。
- **胜负**：摧毁橙色核心即获胜；部队全灭且无可部署单位则失败。
- **寻路**：多源 BFS 以所有建筑为吸引源，进攻单位自动向最近建筑推进；城墙阻挡并需被击破。
- **数值**：城墙 HP 280→160，进攻单位 HP 60，单次拆墙 30，防御塔每 tick 16 伤害。
- **HUD**：显示状态（待命/进攻中/胜利/失败）、在场/总兵力、三兵种剩余数量、操作提示。

## 验证结果
```
VALIDATE_START godot=4.6.3-stable (official) main_ok=true hud_ok=true
A grid=20 core=1 walls=36 defense=4 prod=2 army=58
A deployed=58 army_left=0 state=combat
A end state=win ticks=16 core_hp=-1 units_left=52
B end state=fail ticks=48 (期望 fail：兵尽)
C total_shots=41 fire_ok=true
VALIDATE_OK
```
- 窗口模式 `--shot` 已确认：部队从四周边缘下兵、城墙包围核心、防御塔开火、HUD 状态与兵力正常。

## 关键文件
- `core/battle_sim.gd`：敌方基地生成、部队配额与 `deploy()`、COC 式寻路与胜负判定。
- `core/room_defs.gd`：城墙 HP 调整为 COC 式高血量。
- `core/zombie.gd`：进攻单位 HP 提升。
- `main.gd`：输入改为下兵，移除建造/拆除/升级，单位渲染与特效保留。
- `hud.gd`：改为显示部队与 COC 进攻状态。
- `tools/validate.gd`：新校验场景（可获胜 / 兵尽失败 / 防御塔开火）。
