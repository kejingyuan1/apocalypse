extends Control

## Fallout / Pip-Boy 风格底部交互菜单
## 取代原来的 123/BSV 文字说明，提供图标化按钮与点击反馈。

@export var main_path: NodePath = NodePath("../../")

const RoomDefs := preload("res://core/room_defs.gd")
const Zombie := preload("res://core/zombie.gd")

const PANEL_H: float = 92.0
const BTN_H: float = 56.0
const BTN_PAD: float = 10.0
const BTN_GAP: float = 8.0
const FONT_SIZE: int = 14
const SMALL_FONT: int = 11

const C_PANEL_BG := Color(0.04, 0.06, 0.04, 0.92)
const C_PANEL_BORDER := Color(0.35, 0.78, 0.35, 0.85)
const C_BUTTON_BG := Color(0.08, 0.14, 0.08, 0.95)
const C_BUTTON_HOVER := Color(0.18, 0.36, 0.18, 0.98)
const C_BUTTON_ACTIVE := Color(0.28, 0.55, 0.28, 0.98)
const C_TEXT := Color(0.78, 0.95, 0.78, 1.0)
const C_TEXT_DIM := Color(0.55, 0.70, 0.55, 1.0)
const C_WARN := Color(0.95, 0.55, 0.30, 1.0)
const C_ACCENT := Color(0.35, 0.90, 0.45, 1.0)

var main: Node
var buttons: Array[Dictionary] = []
var hover_idx: int = -1

func _ready() -> void:
	main = get_node_or_null(main_path)
	# Use top-left anchoring so explicit position/size are authoritative (no anchor override warning).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_on_size_changed)
	_on_size_changed()

func _on_size_changed() -> void:
	var vp: Vector2 = get_viewport_rect().size
	position = Vector2(0.0, vp.y - PANEL_H)
	size = Vector2(vp.x, PANEL_H)
	_rebuild_buttons()

func _rebuild_buttons() -> void:
	buttons.clear()
	if main == null:
		return
	var W: float = size.x
	var mode: String = main.game_mode if main.get("game_mode") else "editor"
	var left_x: float = 140.0
	var right_x: float = W - 112.0
	var y: float = (PANEL_H - BTN_H) * 0.5

	if mode == "editor":
		_add_btn(left_x, y, 64.0, BTN_H, "城墙", RoomDefs.Type.WALL, "Q")
		_add_btn(left_x + 72.0, y, 64.0, BTN_H, "防御", RoomDefs.Type.DEFENSE, "W")
		_add_btn(left_x + 144.0, y, 64.0, BTN_H, "生产", RoomDefs.Type.PRODUCTION, "E")
		_add_btn(left_x + 216.0, y, 64.0, BTN_H, "核心", RoomDefs.Type.COMMAND, "R")
		_add_btn(left_x + 296.0, y, 56.0, BTN_H, "升级", -1, "U", true)
		_add_btn(left_x + 360.0, y, 56.0, BTN_H, "清空", -2, "", true)
		_add_btn(right_x - 128.0, y, 56.0, BTN_H, "保存", -3, "", true)
		_add_btn(right_x - 64.0, y, 56.0, BTN_H, "加载", -4, "", true)
	else:
		_add_btn(left_x, y, 70.0, BTN_H, "突击兵", Zombie.Kind.WALKER, "1")
		_add_btn(left_x + 78.0, y, 70.0, BTN_H, "突袭兵", Zombie.Kind.RUNNER, "2")
		_add_btn(left_x + 156.0, y, 70.0, BTN_H, "喷吐者", Zombie.Kind.SPITTER, "3")
		_add_btn(left_x + 242.0, y, 64.0, BTN_H, "清路径", -5, "C", true)

	# 公共按钮：天气、模式切换
	var weather_x: float = right_x + 8.0
	_add_btn(weather_x, y, 56.0, BTN_H, "天气", -10, "V", true)
	var mode_label: String = "进攻" if mode == "editor" else "编辑"
	_add_btn(weather_x + 64.0, y, 56.0, BTN_H, mode_label, -11, "", true)

func _add_btn(x: float, y: float, w: float, h: float, label: String, id: int, key: String, is_action: bool = false) -> void:
	buttons.append({
		"rect": Rect2(x, y, w, h),
		"label": label,
		"id": id,
		"key": key,
		"action": is_action,
	})

func _draw() -> void:
	var W: float = size.x
	var mode: String = main.game_mode if main and main.get("game_mode") else "editor"
	# 底栏面板
	draw_rect(Rect2(0.0, 0.0, W, PANEL_H), C_PANEL_BG)
	draw_line(Vector2(0.0, 0.0), Vector2(W, 0.0), C_PANEL_BORDER, 2.0)

	# 左侧 Vault-Tec 风格标识 + 模式名
	var title: String = "VAULT OS 77" if mode == "editor" else "RAID LINK"
	draw_string(ThemeDB.fallback_font, Vector2(18.0, 28.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_ACCENT)
	var sub: String = "基地编辑" if mode == "editor" else "进攻模式"
	draw_string(ThemeDB.fallback_font, Vector2(18.0, 50.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TEXT_DIM)
	# 小VaultBoy占位图标（简单头像框）
	draw_rect(Rect2(18.0, 56.0, 32.0, 28.0), Color(0.1, 0.22, 0.1, 1.0), false, 2.0)
	draw_circle(Vector2(34.0, 66.0), 6.0, C_TEXT_DIM)
	draw_rect(Rect2(28.0, 74.0, 12.0, 6.0), C_TEXT_DIM)

	# 天气状态小标签
	var weather_name: String = "晴朗"
	if main and main.has_method("_cycle_weather"):
		var wl = main.get_node_or_null("WeatherLayer")
		if wl and wl.has_method("weather_name"):
			weather_name = wl.weather_name()
	draw_string(ThemeDB.fallback_font, Vector2(W - 140.0, 24.0), "天气: %s" % weather_name, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT, C_TEXT_DIM)

	# 按钮
	var mp: Vector2 = get_local_mouse_position()
	hover_idx = -1
	for i: int in range(buttons.size()):
		var b: Dictionary = buttons[i]
		var r: Rect2 = b["rect"]
		var hovered: bool = r.has_point(mp)
		if hovered:
			hover_idx = i
		var active: bool = _is_active(b)
		var bg: Color = C_BUTTON_ACTIVE if active else (C_BUTTON_HOVER if hovered else C_BUTTON_BG)
		draw_rect(r, bg)
		draw_rect(r, C_PANEL_BORDER, false, 1.5)
		var col: Color = C_TEXT if active or hovered else C_TEXT_DIM
		var center: Vector2 = r.get_center()
		draw_string(ThemeDB.fallback_font, Vector2(center.x - 20.0, center.y - 2.0), b["label"], HORIZONTAL_ALIGNMENT_CENTER, 40, FONT_SIZE, col)
		if b["key"] != "":
			draw_string(ThemeDB.fallback_font, Vector2(center.x - 6.0, center.y + 14.0), "[%s]" % b["key"], HORIZONTAL_ALIGNMENT_CENTER, 40, SMALL_FONT, C_TEXT_DIM)

func _is_active(b: Dictionary) -> bool:
	if main == null:
		return false
	var mode: String = main.game_mode if main.get("game_mode") else "editor"
	var id: int = int(b["id"])
	if mode == "editor":
		if id >= 0 and id <= 3:
			return int(main.editor_selected_type) == id
		return false
	else:
		if id >= 0 and id <= 2:
			return main.selected_kinds.has(id)
		return false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = get_local_mouse_position()
		for b: Dictionary in buttons:
			if b["rect"].has_point(mp):
				_trigger(b)
				accept_event()
				return
	elif event is InputEventMouseMotion:
		queue_redraw()

func _trigger(b: Dictionary) -> void:
	if main == null:
		return
	var id: int = int(b["id"])
	var mode: String = main.game_mode if main.get("game_mode") else "editor"
	match id:
		RoomDefs.Type.WALL, RoomDefs.Type.DEFENSE, RoomDefs.Type.PRODUCTION, RoomDefs.Type.COMMAND:
			main.menu_select_room(id)
		Zombie.Kind.WALKER, Zombie.Kind.RUNNER, Zombie.Kind.SPITTER:
			main.menu_toggle_kind(id)
		-1:
			main.menu_upgrade_wall()
		-2:
			main.menu_clear_layout()
		-3:
			main.menu_save_layout()
		-4:
			main.menu_load_layout()
		-5:
			if main.sim and main.sim.has_method("clear_waypoints"):
				main.sim.clear_waypoints()
		-10:
			main.menu_cycle_weather()
		-11:
			if mode == "editor":
				main.enter_attack_mode()
			else:
				main.enter_editor_mode()
	_rebuild_buttons()
	queue_redraw()
