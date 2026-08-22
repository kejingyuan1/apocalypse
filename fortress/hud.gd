extends CanvasLayer

const Zombie := preload("res://core/zombie.gd")

# HUD（横屏全宽自适应；顶部状态条 + 中部消息 + Fallout 底部菜单）

const DANGER_ORANGE := Color(0.91, 0.57, 0.24)   # #E8762E
const COLOR_PANEL := Color(0.08, 0.09, 0.10, 0.90)
const COLOR_PANEL_BORDER := Color(0.30, 0.28, 0.26)

@onready var label = $Label
@onready var tip = $Tip

var msg_label: Label
var top_panel: Panel
var fallout_menu: Control

func _ready() -> void:
	top_panel = Panel.new()
	top_panel.name = "TopPanel"
	var ts := StyleBoxFlat.new()
	ts.bg_color = COLOR_PANEL
	ts.border_color = COLOR_PANEL_BORDER
	ts.border_width_bottom = 2
	top_panel.add_theme_stylebox_override("panel", ts)
	add_child(top_panel)
	move_child(top_panel, 0)

	# 隐藏旧的底部提示节点（由 FalloutMenu 取代）
	tip.hide()

	msg_label = _make_label(0, 0, 500, 64, 30)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	msg_label.add_theme_constant_override("outline_size", 5)
	msg_label.hide()

	# Fallout 风格底部交互菜单
	fallout_menu = preload("res://ui/fallout_menu.gd").new()
	fallout_menu.name = "FalloutMenu"
	fallout_menu.main_path = NodePath("../..")
	add_child(fallout_menu)

	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var W: float = get_viewport().size.x
	top_panel.position = Vector2( 0, 0)
	top_panel.size = Vector2(W, 44)
	label.position = Vector2(0, 0)
	label.size = Vector2(W, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	msg_label.position = Vector2(W / 2.0 - 250, get_viewport().size.y / 2.0 - 32)
	msg_label.size = Vector2(500, 64)
	if toast_label:
		toast_label.position = Vector2(W / 2.0 - 200, get_viewport().size.y - 148)
		toast_label.size = Vector2(400, 40)

func _make_label(x: float, y: float, w: float, h: float, font_size: int) -> Label:
	var lab := Label.new()
	lab.position = Vector2(x, y)
	lab.size = Vector2(w, h)
	lab.add_theme_font_size_override("font_size", font_size)
	add_child(lab)
	return lab

var toast_label: Label
var toast_tween: Tween = null

func _setup_toast() -> void:
	toast_label = _make_label(0, 0, 400, 40, 18)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	toast_label.add_theme_constant_override("outline_size", 5)
	toast_label.hide()

# army: Dictionary(kind -> 剩余数量)；alive: 在场单位数；total: 初始总兵力；selected_kinds: 已选兵种列表
func set_state(state: String, army: Dictionary, alive: int, total: int, selected_kinds: Array, mode: String = "attack", editor_type: int = 0) -> void:
	if toast_label == null:
		_setup_toast()
		_layout()

	var t: String = "待命" if state == "deploy" else ("进攻中" if state == "combat" else ("胜利" if state == "win" else "失败"))
	if mode == "editor":
		label.text = "基地编辑器 | 在场单位 %d" % alive
	else:
		label.text = "状态:%s   |   在场 %d / 总兵力 %d" % [t, alive, total]
	label.add_theme_color_override("font_color", DANGER_ORANGE)

	if fallout_menu:
		fallout_menu.queue_redraw()

	match state:
		"deploy", "combat":
			if state == "deploy" and mode == "attack":
				_show_msg("进攻开始：从四周任意位置下兵！", DANGER_ORANGE)
		"win":
			_show_msg("胜利！敌方堡垒沦陷", DANGER_ORANGE)
		"fail":
			_show_msg("失败！攻势被瓦解", Color(0.88, 0.32, 0.32))

func _show_msg(text: String, col: Color) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", col)
	msg_label.show()
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_callback(func(): msg_label.hide())

func show_toast(text: String, col: Color) -> void:
	if toast_label == null:
		_setup_toast()
		_layout()
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", col)
	toast_label.show()
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(1.8)
	toast_tween.tween_callback(func(): toast_label.hide())
