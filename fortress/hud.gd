extends CanvasLayer

# HUD（横屏全宽自适应；单层暖橙威胁色，美术圣经铁律）

const DANGER_ORANGE := Color(0.91, 0.57, 0.24)   # #E8762E
const COLOR_SCRAP := Color(0.90, 0.74, 0.28)     # 废料金黄
const COLOR_BIOMASS := Color(0.40, 0.80, 0.42)   # 生物质绿
const COLOR_PANEL := Color(0.08, 0.09, 0.10, 0.90)
const COLOR_PANEL_BORDER := Color(0.30, 0.28, 0.26)
const COLOR_TEXT := Color(0.88, 0.88, 0.88)

@onready var label = $Label
@onready var tip = $Tip

var scrap_label: Label
var biomass_label: Label
var sel_label: Label
var msg_label: Label
var top_panel: Panel

func _ready() -> void:
	# 顶部状态条背景
	top_panel = Panel.new()
	top_panel.name = "TopPanel"
	var ts := StyleBoxFlat.new()
	ts.bg_color = COLOR_PANEL
	ts.border_color = COLOR_PANEL_BORDER
	ts.border_width_bottom = 2
	top_panel.add_theme_stylebox_override("panel", ts)
	add_child(top_panel)
	move_child(top_panel, 0)

	scrap_label = _make_label(16, 0, 220, 22, 16)
	biomass_label = _make_label(16, 26, 220, 22, 16)
	sel_label = _make_label(0, 0, 320, 24, 17)

	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	msg_label = _make_label(0, 0, 500, 64, 30)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	msg_label.add_theme_constant_override("outline_size", 5)
	msg_label.hide()

	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var W: float = get_viewport().size.x
	var H: float = get_viewport().size.y
	top_panel.position = Vector2(0, 0)
	top_panel.size = Vector2(W, 44)
	label.position = Vector2(0, 0)
	label.size = Vector2(W, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	# 底部建造面板
	var bh := 88.0
	if not has_node("BottomPanel"):
		var panel := Panel.new()
		panel.name = "BottomPanel"
		var bs := StyleBoxFlat.new()
		bs.bg_color = COLOR_PANEL
		bs.border_color = COLOR_PANEL_BORDER
		bs.border_width_top = 2
		panel.add_theme_stylebox_override("panel", bs)
		add_child(panel)
		move_child(panel, 1)
	var bp := get_node("BottomPanel")
	bp.position = Vector2(0, H - bh)
	bp.size = Vector2(W, bh)
	# 底部控件
	scrap_label.position = Vector2(20, H - bh + 14)
	biomass_label.position = Vector2(20, H - bh + 44)
	sel_label.position = Vector2(260, H - bh + 30)
	tip.position = Vector2(W - 640, H - bh + 30)
	tip.size = Vector2(620, 30)
	msg_label.position = Vector2(W / 2.0 - 250, H / 2.0 - 32)
	msg_label.size = Vector2(500, 64)

func _make_label(x: float, y: float, w: float, h: float, font_size: int) -> Label:
	var lab := Label.new()
	lab.position = Vector2(x, y)
	lab.size = Vector2(w, h)
	lab.add_theme_font_size_override("font_size", font_size)
	add_child(lab)
	return lab

func set_state(state: String, wave: int, remaining: int, scrap: int, biomass: int, sel: int) -> void:
	var t: String = "建造" if state == "build" else ("战斗" if state == "combat" else ("胜利" if state == "win" else "失败"))
	label.text = "状态:%s   |   波次:%d/10   |   剩余丧尸:%d" % [t, wave, remaining]
	label.add_theme_color_override("font_color", DANGER_ORANGE)

	scrap_label.text = "废料  %d" % scrap
	scrap_label.add_theme_color_override("font_color", COLOR_SCRAP)
	biomass_label.text = "生物质  %d" % biomass
	biomass_label.add_theme_color_override("font_color", COLOR_BIOMASS)

	var names := ["城墙", "防御", "生产", "指挥"]
	var costs := [20, 40, 30, 0]
	var sel_name: String = names[sel] if sel < names.size() else str(sel)
	var sel_cost: int = costs[sel] if sel < costs.size() else 0
	sel_label.text = "选中: %s  (%d 废料)" % [sel_name, sel_cost]
	sel_label.add_theme_color_override("font_color", COLOR_TEXT)

	match state:
		"build":
			tip.text = "左键放置 | 右键/X 拆除(返还50%) | U 升级(15废料) | 1城墙 2防御 3生产 | 空格开波"
			msg_label.hide()
		"combat":
			tip.text = "尸潮从山洞涌入！防御塔自动开火，丧尸破墙逼近核心"
			_show_msg("第 %d 波入侵！" % wave, DANGER_ORANGE)
		"win":
			tip.text = "守住前 10 波，堡垒存续！"
			_show_msg("胜利！堡垒存续", DANGER_ORANGE)
		"fail":
			tip.text = "指挥核心被摧毁！"
			_show_msg("失败！核心被毁", Color(0.88, 0.32, 0.32))

func _show_msg(text: String, col: Color) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", col)
	msg_label.show()
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_callback(func(): msg_label.hide())
