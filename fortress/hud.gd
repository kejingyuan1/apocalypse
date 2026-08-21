extends CanvasLayer

# HUD（对齐《美术圣经》单层暖橙威胁色，不用红色；波次 §4.3 三态）

const DANGER_ORANGE := Color(0.91, 0.57, 0.24)   # #E8762E 单层暖橙铁律
const COLOR_SCRAP := Color(0.85, 0.70, 0.25)     # 废料金黄
const COLOR_BIOMASS := Color(0.35, 0.75, 0.35)   # 生物质绿
const COLOR_PANEL := Color(0.10, 0.11, 0.12, 0.92)
const COLOR_PANEL_BORDER := Color(0.25, 0.26, 0.28)

@onready var label = $Label
@onready var tip = $Tip

var scrap_label: Label
var biomass_label: Label
var sel_label: Label
var msg_label: Label

func _ready() -> void:
	# 顶部状态条
	label.position = Vector2(0, 0)
	label.size = Vector2(1152, 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)

	# 底部操作 + 资源面板
	var panel := Panel.new()
	panel.name = "BottomPanel"
	panel.position = Vector2(0, 648 - 72)
	panel.size = Vector2(1152, 72)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.border_width_top = 2
	panel_style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	move_child(panel, 0)

	# 资源文本
	scrap_label = _make_label(Vector2(16, 648 - 60), 200, 22, 16)
	biomass_label = _make_label(Vector2(16, 648 - 34), 200, 22, 16)
	sel_label = _make_label(Vector2(240, 648 - 60), 260, 22, 16)

	# 操作提示
	tip.position = Vector2(520, 648 - 56)
	tip.size = Vector2(620, 40)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 14)

	# 中央大消息（波次/胜利/失败）
	msg_label = _make_label(Vector2(576 - 200, 324 - 30), 400, 60, 28)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	msg_label.add_theme_constant_override("outline_size", 4)
	msg_label.hide()

func _make_label(pos: Vector2, w: float, h: float, font_size: int) -> Label:
	var lab := Label.new()
	lab.position = pos
	lab.size = Vector2(w, h)
	lab.add_theme_font_size_override("font_size", font_size)
	add_child(lab)
	return lab

func set_state(state: String, wave: int, remaining: int, scrap: int, biomass: int, sel: int) -> void:
	var t: String = "建造" if state == "build" else ("战斗" if state == "combat" else ("胜利" if state == "win" else "失败"))
	label.text = "状态:%s  |  波次:%d/10  |  剩余丧尸:%d" % [t, wave, remaining]
	label.add_theme_color_override("font_color", DANGER_ORANGE)

	scrap_label.text = "废料: %d" % scrap
	scrap_label.add_theme_color_override("font_color", COLOR_SCRAP)
	biomass_label.text = "生物质: %d" % biomass
	biomass_label.add_theme_color_override("font_color", COLOR_BIOMASS)

	var names := ["城墙", "防御", "生产", "指挥"]
	var costs := [20, 40, 30, 0]
	var sel_name: String = names[sel] if sel < names.size() else str(sel)
	var sel_cost: int = costs[sel] if sel < costs.size() else 0
	sel_label.text = "选中: %s (%d 废料)" % [sel_name, sel_cost]
	sel_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

	match state:
		"build":
			tip.text = "左键放置 | 右键/X 拆除(返还50%) | U 升级(15废料) | 1城墙 2防御 3生产 | 空格开波"
			msg_label.hide()
		"combat":
			tip.text = "尸潮来袭！防御塔自动开火，丧尸破墙逼近核心"
			_show_msg("第 %d 波入侵！" % wave, DANGER_ORANGE)
		"win":
			tip.text = "守住前 10 波，堡垒存续！"
			_show_msg("胜利！堡垒存续", DANGER_ORANGE)
		"fail":
			tip.text = "指挥核心被摧毁！"
			_show_msg("失败！核心被毁", Color(0.85, 0.3, 0.3))

func _show_msg(text: String, col: Color) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", col)
	msg_label.show()
	# 1.5 秒后淡出隐藏
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(func(): msg_label.hide())
