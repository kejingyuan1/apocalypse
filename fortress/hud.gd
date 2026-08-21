extends CanvasLayer
class_name HUD

# HUD（对齐《美术圣经》单层暖橙威胁色，不用红色）
@onready var label = $Label
@onready var tip = $Tip

func set_state(state: String, wave: int, remaining: int, scrap: int, sel: int) -> void:
	var t = "建造" if state == "build" else ("战斗" if state == "combat" else "胜利")
	var names = ["城墙", "防御", "生产", "指挥"]
	var sel_name = names[sel] if sel < names.size() else str(sel)
	label.text = "状态:%s  波次:%d/10  剩余丧尸:%d  废料:%d  选中:%s" % [t, wave, remaining, scrap, sel_name]
	label.add_theme_color_override("font_color", Color(0.91, 0.57, 0.24))  # 暖橙 DANGER_ORANGE #E8762E
	tip.text = "左键放置 | 1城墙 2防御 3生产 | 空格开始波次"
