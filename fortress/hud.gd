extends CanvasLayer

# HUD（对齐《美术圣经》单层暖橙威胁色，不用红色；波次 §4.3 三态）
@onready var label = $Label
@onready var tip = $Tip

const DANGER_ORANGE := Color(0.91, 0.57, 0.24)   # #E8762E 单层暖橙铁律

func set_state(state: String, wave: int, remaining: int, scrap: int, biomass: int, sel: int) -> void:
	var t: String = "建造" if state == "build" else ("战斗" if state == "combat" else ("胜利" if state == "win" else "失败"))
	var names := ["城墙", "防御", "生产", "指挥"]
	var costs := [20, 40, 30, 0]
	var sel_name: String = names[sel] if sel < names.size() else str(sel)
	var sel_cost: int = costs[sel] if sel < costs.size() else 0
	label.text = "状态:%s  波次:%d/10  剩余:%d  废料:%d  生物质:%d  选中:%s(%d)" % [t, wave, remaining, scrap, biomass, sel_name, sel_cost]
	label.add_theme_color_override("font_color", DANGER_ORANGE)
	match state:
		"build":
			tip.text = "左键放置 | 右键/X拆除(返还50%) | U升级(15废料) | 1城墙 2防御 3生产 | 空格开波"
		"combat":
			tip.text = "尸潮来袭！防御房自动开火，丧尸破墙逼近核心（暖橙预警）"
		"win":
			tip.text = "守住前 10 波，堡垒存续！按 R 重开（待接入）。"
		"fail":
			tip.text = "指挥核心被摧毁！堡垒重置至 Lv2（待接入重开）。"
