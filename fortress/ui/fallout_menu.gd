extends Control

## COC 风格底部图标菜单
## 使用 AI 生成的彩色图标按钮 + NinePatchRect 面板，取代原来的手绘辐射绿面板。

@export var main_path: NodePath = NodePath("../../")

const RoomDefs := preload("res://core/room_defs.gd")
const Zombie := preload("res://core/zombie.gd")

const PANEL_H: float = 120.0
const BTN_SIZE: float = 86.0
const ROW_SEPARATION: int = 14

@onready var _panel: NinePatchRect = NinePatchRect.new()
@onready var _row: HBoxContainer = HBoxContainer.new()

var main: Node = null
var _weather_btn: TextureButton = null
var _mode_btn: TextureButton = null
var _room_buttons: Dictionary[int, TextureButton] = {}
var _zombie_buttons: Dictionary[int, TextureButton] = {}
var _editor_buttons: Array[TextureButton] = []
var _attack_buttons: Array[TextureButton] = []

func _ready() -> void:
	main = get_node_or_null(main_path)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_add_panel()
	_add_button_row()
	_layout()
	refresh()
	get_viewport().size_changed.connect(_layout)

func _add_panel() -> void:
	_panel.name = "MenuPanel"
	_panel.texture = load("res://assets/ui/menu_bar_bg.png") as Texture2D
	_panel.patch_margin_left = 180
	_panel.patch_margin_right = 180
	_panel.patch_margin_top = 50
	_panel.patch_margin_bottom = 50
	add_child(_panel)

func _add_button_row() -> void:
	_row.name = "ButtonRow"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", ROW_SEPARATION)
	add_child(_row)

	# 编辑器房间按钮
	_room_buttons[RoomDefs.Type.WALL] = _add_btn("res://assets/ui/btn_wall.png", _on_wall, "城墙 (Q)", _editor_buttons)
	_room_buttons[RoomDefs.Type.DEFENSE] = _add_btn("res://assets/ui/btn_defense.png", _on_defense, "防御 (W)", _editor_buttons)
	_room_buttons[RoomDefs.Type.PRODUCTION] = _add_btn("res://assets/ui/btn_production.png", _on_production, "生产 (E)", _editor_buttons)
	_room_buttons[RoomDefs.Type.COMMAND] = _add_btn("res://assets/ui/btn_core.png", _on_core, "核心 (R)", _editor_buttons)

	# 编辑器系统按钮
	_editor_buttons.append(_add_btn("res://assets/ui/btn_upgrade.png", _on_upgrade, "升级 (U)", _editor_buttons))
	_editor_buttons.append(_add_btn("res://assets/ui/btn_clear.png", _on_clear_layout, "清空布局", _editor_buttons))
	_editor_buttons.append(_add_btn("res://assets/ui/btn_save.png", _on_save, "保存布局", _editor_buttons))
	_editor_buttons.append(_add_btn("res://assets/ui/btn_load.png", _on_load, "加载布局", _editor_buttons))

	# 进攻兵种按钮
	_zombie_buttons[Zombie.Kind.WALKER] = _add_btn("res://assets/ui/btn_zombie_walker.png", _on_walker, "突击兵 (1)", _attack_buttons)
	_zombie_buttons[Zombie.Kind.RUNNER] = _add_btn("res://assets/ui/btn_zombie_runner.png", _on_runner, "突袭兵 (2)", _attack_buttons)
	_zombie_buttons[Zombie.Kind.SPITTER] = _add_btn("res://assets/ui/btn_zombie_spitter.png", _on_spitter, "喷吐者 (3)", _attack_buttons)
	_attack_buttons.append(_add_btn("res://assets/ui/btn_clear.png", _on_clear_waypoints, "清除路径 (C)", _attack_buttons))

	# 公共按钮
	_weather_btn = _add_btn("res://assets/ui/btn_weather_clear.png", _on_weather, "切换天气 (V)")
	_mode_btn = _add_btn("res://assets/ui/btn_mode_attack.png", _on_mode, "切换模式")

func _add_btn(tex_path: String, callback: Callable, tooltip: String, group: Array[TextureButton] = []) -> TextureButton:
	var btn := TextureButton.new()
	btn.name = tooltip.split(" ")[0]
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var tex: Texture2D = load(tex_path) as Texture2D
	if tex != null:
		btn.texture_normal = tex
	else:
		push_warning("FalloutMenu: failed to load %s" % tex_path)
	btn.pressed.connect(callback)
	btn.mouse_entered.connect(_on_btn_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_btn_hover.bind(btn, false))
	_row.add_child(btn)
	if group.size() > 0:
		group.append(btn)
	return btn

func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	position = Vector2(0.0, vp.y - PANEL_H)
	size = Vector2(vp.x, PANEL_H)

	_panel.position = Vector2(0.0, 0.0)
	_panel.size = Vector2(vp.x, PANEL_H)

	_row.position = Vector2(0.0, (PANEL_H - BTN_SIZE) * 0.5)
	_row.size = Vector2(vp.x, BTN_SIZE)

func _on_btn_hover(btn: TextureButton, hovered: bool) -> void:
	var base: float = _base_scale(btn)
	var target: float = base * (1.12 if hovered else 1.0)
	var tw: Tween = create_tween()
	tw.tween_property(btn, "scale", Vector2(target, target), 0.12)

func _base_scale(btn: TextureButton) -> float:
	if main == null:
		return 1.0
	var mode: String = main.game_mode if main.get("game_mode") else "editor"
	if mode == "editor":
		if _room_buttons.has(main.editor_selected_type) and _room_buttons[main.editor_selected_type] == btn:
			return 1.15
	else:
		if main.selected_kinds.has(Zombie.Kind.WALKER) and _zombie_buttons.has(Zombie.Kind.WALKER) and _zombie_buttons[Zombie.Kind.WALKER] == btn:
			return 1.15
		if main.selected_kinds.has(Zombie.Kind.RUNNER) and _zombie_buttons.has(Zombie.Kind.RUNNER) and _zombie_buttons[Zombie.Kind.RUNNER] == btn:
			return 1.15
		if main.selected_kinds.has(Zombie.Kind.SPITTER) and _zombie_buttons.has(Zombie.Kind.SPITTER) and _zombie_buttons[Zombie.Kind.SPITTER] == btn:
			return 1.15
	return 1.0

func refresh() -> void:
	if main == null:
		return
	var mode: String = main.game_mode if main.get("game_mode") else "editor"
	var is_editor: bool = mode == "editor"

	# 切换可见分组
	for btn: TextureButton in _editor_buttons:
		btn.visible = is_editor
	for btn: TextureButton in _attack_buttons:
		btn.visible = not is_editor

	# 房间类型高亮
	for type_id: int in _room_buttons.keys():
		var btn: TextureButton = _room_buttons[type_id]
		var selected: bool = is_editor and int(main.editor_selected_type) == type_id
		btn.modulate = Color(1.25, 1.25, 1.25) if selected else Color.WHITE
		btn.scale = Vector2(1.15, 1.15) if selected else Vector2.ONE

	# 兵种高亮
	for kind: int in _zombie_buttons.keys():
		var btn: TextureButton = _zombie_buttons[kind]
		var selected: bool = (not is_editor) and main.selected_kinds.has(kind)
		btn.modulate = Color(1.25, 1.25, 1.25) if selected else Color.WHITE
		btn.scale = Vector2(1.15, 1.15) if selected else Vector2.ONE

	# 天气按钮显示当前天气
	var weather: String = "clear"
	if main.sim and main.sim.get("weather"):
		weather = main.sim.weather
	var weather_tex: String = "res://assets/ui/btn_weather_clear.png"
	match weather:
		"rain": weather_tex = "res://assets/ui/btn_weather_rain.png"
		"snow": weather_tex = "res://assets/ui/btn_weather_snow.png"
	_weather_btn.texture_normal = load(weather_tex) as Texture2D

	# 模式按钮显示点击后将进入的模式
	var mode_tex: String = "res://assets/ui/btn_mode_attack.png" if is_editor else "res://assets/ui/btn_mode_editor.png"
	_mode_btn.texture_normal = load(mode_tex) as Texture2D
	_mode_btn.tooltip_text = "进攻模式" if is_editor else "编辑模式"

func _on_wall() -> void:
	if main != null:
		main.menu_select_room(RoomDefs.Type.WALL)
		refresh()

func _on_defense() -> void:
	if main != null:
		main.menu_select_room(RoomDefs.Type.DEFENSE)
		refresh()

func _on_production() -> void:
	if main != null:
		main.menu_select_room(RoomDefs.Type.PRODUCTION)
		refresh()

func _on_core() -> void:
	if main != null:
		main.menu_select_room(RoomDefs.Type.COMMAND)
		refresh()

func _on_upgrade() -> void:
	if main != null:
		main.menu_upgrade_wall()

func _on_clear_layout() -> void:
	if main != null:
		main.menu_clear_layout()

func _on_save() -> void:
	if main != null:
		main.menu_save_layout()

func _on_load() -> void:
	if main != null:
		main.menu_load_layout()

func _on_walker() -> void:
	if main != null:
		main.menu_toggle_kind(Zombie.Kind.WALKER)
		refresh()

func _on_runner() -> void:
	if main != null:
		main.menu_toggle_kind(Zombie.Kind.RUNNER)
		refresh()

func _on_spitter() -> void:
	if main != null:
		main.menu_toggle_kind(Zombie.Kind.SPITTER)
		refresh()

func _on_clear_waypoints() -> void:
	if main != null and main.sim != null and main.sim.has_method("clear_waypoints"):
		main.sim.clear_waypoints()

func _on_weather() -> void:
	if main != null:
		main.menu_cycle_weather()
		refresh()

func _on_mode() -> void:
	if main == null:
		return
	if main.game_mode == "editor":
		main.enter_attack_mode()
	else:
		main.enter_editor_mode()
	refresh()
