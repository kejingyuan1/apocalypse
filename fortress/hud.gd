extends CanvasLayer

const Zombie := preload("res://core/zombie.gd")

# HUD（横屏全宽自适应；单层暖橙威胁色，美术圣经铁律）

const DANGER_ORANGE := Color(0.91, 0.57, 0.24)   # #E8762E
const COLOR_PANEL := Color(0.08, 0.09, 0.10, 0.90)
const COLOR_PANEL_BORDER := Color(0.30, 0.28, 0.26)
const COLOR_TEXT := Color(0.88, 0.88, 0.88)
const COLOR_OK := Color(0.45, 0.82, 0.45)         # 选中兵种高亮（绿）

@onready var label = $Label
@onready var tip = $Tip

var msg_label: Label
var top_panel: Panel
var kind_labels: Array = []
var kind_keys: Array = [Zombie.Kind.WALKER, Zombie.Kind.RUNNER, Zombie.Kind.SPITTER]
var kind_names: Dictionary = {
	Zombie.Kind.WALKER: "突击兵",
	Zombie.Kind.RUNNER: "突袭兵",
	Zombie.Kind.SPITTER: "喷吐者",
}

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

	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	msg_label = _make_label(0, 0, 500, 64, 30)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	msg_label.add_theme_constant_override("outline_size", 5)
	msg_label.hide()

	for i in range(3):
		var lab := _make_label(0, 0, 200, 30, 17)
		kind_labels.append(lab)

	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var W: float = get_viewport().size.x
	var H: float = get_viewport().size.y
	top_panel.position = Vector2( 0, 0)
	top_panel.size = Vector2(W, 44)
	label.position = Vector2(0, 0)
	label.size = Vector2(W, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)

	var bh := 92.0
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
	for i in range(3):
		kind_labels[i].position = Vector2(24 + i * 210, H - bh + 32)
	tip.position = Vector2(W - 640, H - bh + 32)
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

# army: Dictionary(kind -> 剩余数量)；alive: 在场单位数；total: 初始总兵力；selected_kind: 当前选中兵种
func set_state(state: String, army: Dictionary, alive: int, total: int, selected_kind: int) -> void:
	var t: String = "待命" if state == "deploy" else ("进攻中" if state == "combat" else ("胜利" if state == "win" else "失败"))
	label.text = "状态:%s   |   在场 %d / 总兵力 %d" % [t, alive, total]
	label.add_theme_color_override("font_color", DANGER_ORANGE)

	for i in range(3):
		var k: int = kind_keys[i]
		var cnt: int = army.get(k, 0)
		var lab: Label = kind_labels[i]
		lab.text = "%d  %s  ×%d" % [i + 1, kind_names[k], cnt]
		lab.add_theme_color_override("font_color", COLOR_OK if k == selected_kind else COLOR_TEXT)

	match state:
		"deploy", "combat":
			tip.text = "左键在任意空地投放部队 | 1突击 2突袭 3喷吐 | 摧毁橙色核心即胜 | 部队耗尽则败"
			if state == "deploy":
				_show_msg("进攻开始：从四周任意位置下兵！", DANGER_ORANGE)
		"win":
			tip.text = "敌方核心已被摧毁！"
			_show_msg("胜利！敌方堡垒沦陷", DANGER_ORANGE)
		"fail":
			tip.text = "部队全军覆没！"
			_show_msg("失败！攻势被瓦解", Color(0.88, 0.32, 0.32))

func _show_msg(text: String, col: Color) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", col)
	msg_label.show()
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_callback(func(): msg_label.hide())
