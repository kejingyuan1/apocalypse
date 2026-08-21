extends Node2D

# 《末日堡垒 · COC 式进攻》渲染/输入翻译层
# 逻辑全部在 core/（服务端可移植），本脚本只做输入翻译 + 节点级动画渲染。
# 主题：山中堡垒（凿穿山体建成的地下要塞）+ COC 式进攻：玩家带兵从四周任意空地下兵。
# 渲染管线：背景层(BGLayer._draw) -> 单位层(AnimatedSprite2D) -> 特效层(FXLayer._draw)。

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Zombie := preload("res://core/zombie.gd")
const HUD := preload("res://hud.gd")

const TILE := 64               # 单元格像素（与精灵表帧尺寸一致）
const HUD_TOP := 44.0
const HUD_BOTTOM := 92.0
const SPRITE_SIZE := 64

# —— 配色（末日地下堡垒：冷岩 + 暖橙威胁色）——
const COLOR_SKY := Color(0.04, 0.05, 0.07)
const COLOR_ROCK := Color(0.13, 0.12, 0.13)
const COLOR_ROCK_HI := Color(0.20, 0.19, 0.20)
const COLOR_ROCK_LO := Color(0.07, 0.07, 0.08)
const COLOR_FLOOR_A := Color(0.12, 0.12, 0.13)
const COLOR_FLOOR_B := Color(0.10, 0.10, 0.11)
const COLOR_GRID := Color(0.32, 0.30, 0.28, 0.45)
const COLOR_GRID_STRONG := Color(0.45, 0.42, 0.38, 0.55)
const COLOR_DEPLOY_OK := Color(0.30, 0.75, 0.40, 0.40)
const COLOR_DEPLOY_BAD := Color(0.90, 0.25, 0.25, 0.40)
const COLOR_HP_BG := Color(0.10, 0.10, 0.10)
const COLOR_HP_GREEN := Color(0.35, 0.82, 0.40)
const COLOR_HP_ORANGE := Color(0.91, 0.57, 0.24)
const COLOR_HP_RED := Color(0.88, 0.28, 0.28)
const COLOR_UNIT := {
	Zombie.Kind.WALKER: Color(0.82, 0.52, 0.30),
	Zombie.Kind.RUNNER: Color(0.85, 0.30, 0.30),
	Zombie.Kind.SPITTER: Color(0.72, 0.34, 0.78),
}
const COLOR_BULLET := Color(1.0, 0.92, 0.55)

# —— 血条美术 ——
const HP_BAR_H := 7.0
const HP_BAR_BORDER := 1.0
const HP_BAR_SEGMENTS := 4
const COLOR_HP_BORDER := Color(0.02, 0.02, 0.02, 0.85)
const COLOR_HP_DARK := Color(0.18, 0.18, 0.18, 0.85)
const COLOR_HP_FLASH := Color(1.0, 1.0, 1.0, 0.65)

# —— 精灵表配置（AtlasTexture 切片）——
const ROOM_SHEETS := {
	RoomDefs.Type.WALL:       {"path": "res://assets/sheets/wall.png",       "anim": "wall",  "frames": 8, "fps": 1.0},
	RoomDefs.Type.PRODUCTION: {"path": "res://assets/sheets/production.png",  "anim": "work",  "frames": 4, "fps": 5.0},
	RoomDefs.Type.COMMAND:    {"path": "res://assets/sheets/core.png",        "anim": "pulse", "frames": 4, "fps": 6.0},
}
const TURRET_BASE_SHEET  := {"path": "res://assets/sheets/turret_base.png",  "anim": "base",  "frames": 1, "fps": 1.0}
const TURRET_BARREL_SHEET := {"path": "res://assets/sheets/turret_barrel.png", "anim": "fire",  "frames": 4, "fps": 12.0}
const ZOMBIE_SHEETS := {
	Zombie.Kind.WALKER: "res://assets/sheets/zombie_walker.png",
	Zombie.Kind.RUNNER: "res://assets/sheets/zombie_runner.png",
	Zombie.Kind.SPITTER: "res://assets/sheets/zombie_spitter.png",
}

@onready var hud: HUD = $HUD

var grid: GridModel
var sim: BattleSim

# 模式："attack" = COC 式进攻；"editor" = 基地编辑器
var game_mode: String = "attack"

# 进攻模式：多选兵种 + 拖拽下兵 + 路径点
var selected_kinds: Array = [Zombie.Kind.WALKER]
var drag_deploying: bool = false
var last_deploy_cell: Vector2i = Vector2i(-1, -1)
var deploy_cooldown: float = 0.0
const DEPLOY_INTERVAL: float = 0.045
var waypoints: Array = []            # Vector2 单元坐标
var waypoint_pulse: float = 0.0

# 编辑器模式
var editor_selected_type: int = RoomDefs.Type.WALL
const EDITOR_ROOM_KEYS: Dictionary = {
	KEY_Q: RoomDefs.Type.WALL,
	KEY_W: RoomDefs.Type.DEFENSE,
	KEY_E: RoomDefs.Type.PRODUCTION,
	KEY_R: RoomDefs.Type.COMMAND,
}

var tick_acc: float = 0.0
var camera: Camera2D
var anim_time: float = 0.0
var zoom_level: float = 1.0
var _panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _cam_start: Vector2 = Vector2.ZERO
var base_zoom: float = 1.0

var bg_layer: BGLayer
var ambient_layer: AmbientLayer
var unit_layer: Node2D
var fx_layer: FXLayer
var weather_layer: WeatherLayer
var corner_decal: CornerDecalLayer
var bg_sprite: Sprite2D
var bg_paths: Array = [
	"res://assets/backgrounds/bg_bunker.png",
	"res://assets/backgrounds/bg_forest.png",
	"res://assets/backgrounds/bg_wasteland.png",
]
var bg_index: int = 0

# —— 动画状态 ——
var particles: Array = []
var bullets: Array = []
var floating_text: Array = []
var screen_shake: float = 0.0
var turret_aim: Dictionary = {}
var turret_targets: Dictionary = {}
var turret_flash: Dictionary = {}
var room_flash: Dictionary = {}
var core_flash: float = 0.0
var prev_unit_ids: Dictionary = {}
var prev_room_hp: Dictionary = {}
var prev_core_hp: int = -1
var dust_acc: float = 0.0
var smoke_acc: Dictionary = {}

# —— 实体精灵实例 ——
var room_sprites: Dictionary = {}   # 非防御房间 id -> AnimatedSprite2D
var turret_nodes: Dictionary = {}   # 防御塔 id -> {pivot:Node2D, base:AnimatedSprite2D, barrel:AnimatedSprite2D}
var unit_sprites: Dictionary = {}
var _frames_cache: Dictionary = {}
var _shot_pending: bool = false
var _shot_frames: int = 0
var _intro_tween: Tween = null

func _ready() -> void:
	_setup_layers()
	grid = GridModel.new()
	if OS.get_cmdline_user_args().has("--editor"):
		game_mode = "editor"
	# 战斗内核会自行设定网格尺寸并生成敌方基地
	sim = BattleSim.new(grid)
	_setup_camera()
	_setup_background()
	if game_mode == "attack":
		_try_load_saved_layout()
	_sync_rooms()
	_sync_state()
	ambient_layer.spawn_ambient()
	weather_layer.set_weather("clear")
	_intro_camera()
	if OS.get_cmdline_user_args().has("--shot"):
		_dev_shot_setup()

func _setup_layers() -> void:
	bg_layer = BGLayer.new(); bg_layer.main = self; add_child(bg_layer)
	ambient_layer = AmbientLayer.new(); ambient_layer.main = self; add_child(ambient_layer)
	unit_layer = Node2D.new(); add_child(unit_layer)
	fx_layer = FXLayer.new(); fx_layer.main = self; add_child(fx_layer)
	weather_layer = WeatherLayer.new(); weather_layer.main = self; add_child(weather_layer)
	# 屏幕右下角贴花：遮挡平台水印并增强废墟氛围
	var decal_canvas := CanvasLayer.new()
	decal_canvas.layer = 1
	add_child(decal_canvas)
	corner_decal = CornerDecalLayer.new()
	corner_decal.main = self
	decal_canvas.add_child(corner_decal)

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.position = _grid_center_world()
	add_child(camera)
	camera.make_current()
	_rezoom()
	get_viewport().size_changed.connect(_rezoom)

func _rezoom() -> void:
	if camera == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var world_px: float = float(grid.size) * TILE
	var avail_w: float = max(vp.x - 32.0, 100.0)
	var avail_h: float = max(vp.y - HUD_TOP - HUD_BOTTOM, 100.0)
	base_zoom = clampf(min(avail_w, avail_h) / world_px, 0.02, 10.0)
	_apply_zoom()

func _apply_zoom() -> void:
	if camera == null:
		return
	var z: float = clampf(base_zoom * zoom_level, 0.02, 10.0)
	camera.zoom = Vector2(z, z)

func _grid_center_world() -> Vector2:
	return Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0)

func _intro_camera() -> void:
	if camera == null:
		return
	var start_zoom: float = clampf(base_zoom * 0.55, 0.02, 10.0)
	camera.zoom = Vector2(start_zoom, start_zoom)
	_intro_tween = create_tween()
	_intro_tween.tween_property(camera, "zoom", Vector2(base_zoom, base_zoom), 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _cancel_intro() -> void:
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
		_intro_tween = null

# ===================== 背景皮肤 =====================
func _setup_background() -> void:
	bg_sprite = Sprite2D.new()
	bg_sprite.z_as_relative = false
	bg_sprite.z_index = -10
	bg_sprite.centered = true
	add_child(bg_sprite)
	_set_background(bg_index)

func _set_background(idx: int) -> void:
	bg_index = idx % bg_paths.size()
	var tex := load(bg_paths[bg_index]) as Texture2D
	if tex == null:
		return
	bg_sprite.texture = tex
	var world_px: float = float(grid.size) * TILE
	bg_sprite.scale = Vector2(world_px / tex.get_width(), world_px / tex.get_height())
	bg_sprite.position = _grid_center_world()

func _cycle_weather() -> void:
	var states: Array = ["clear", "rain", "snow"]
	var idx: int = states.find(weather_layer.weather)
	idx = (idx + 1) % states.size()
	weather_layer.set_weather(states[idx])
	_show_toast("天气：%s" % weather_layer.weather_name(), Color(0.6, 0.85, 1.0))

# ===================== 输入 =====================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_cancel_intro()
				var c: Vector2i = world_to_cell(get_global_mouse_position())
				if game_mode == "editor":
					_editor_place(c)
				else:
					if event.shift_pressed:
						_add_waypoint(Vector2(c.x + 0.5, c.y + 0.5))
					else:
						drag_deploying = true
						last_deploy_cell = Vector2i(-1, -1)
						_drag_deploy(c)
			else:
				drag_deploying = false
				last_deploy_cell = Vector2i(-1, -1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cancel_intro()
			_zoom_at(get_global_mouse_position(), 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cancel_intro()
			_zoom_at(get_global_mouse_position(), 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_cancel_intro()
				if game_mode == "editor":
					_editor_remove(world_to_cell(get_global_mouse_position()))
				else:
					_panning = true
					_pan_start = get_global_mouse_position()
					_cam_start = camera.position
			else:
				_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			camera.position = _cam_start - (get_global_mouse_position() - _pan_start) / camera.zoom
		elif drag_deploying and game_mode == "attack":
			var c: Vector2i = world_to_cell(get_global_mouse_position())
			if c != last_deploy_cell and deploy_cooldown <= 0.0:
				_drag_deploy(c)
	elif event is InputEventMagnifyGesture:
		_zoom_at(camera.position, event.factor)
	elif event is InputEventKey and event.pressed:
		if game_mode == "attack":
			match event.keycode:
				KEY_1: _toggle_kind(Zombie.Kind.WALKER)
				KEY_2: _toggle_kind(Zombie.Kind.RUNNER)
				KEY_3: _toggle_kind(Zombie.Kind.SPITTER)
				KEY_C:
					waypoints.clear()
					sim.clear_waypoints()
				KEY_B: _set_background(bg_index + 1)
				KEY_V: _cycle_weather()
		else:
			if EDITOR_ROOM_KEYS.has(event.keycode):
				editor_selected_type = EDITOR_ROOM_KEYS[event.keycode]
			elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_editor_remove(world_to_cell(get_global_mouse_position()))
			elif event.keycode == KEY_S and event.ctrl_pressed:
				_save_layout()
			elif event.keycode == KEY_L and event.ctrl_pressed:
				_load_layout()
			elif event.keycode == KEY_N and event.ctrl_pressed:
				_editor_clear()
			elif event.keycode == KEY_U:
				_editor_upgrade_under_cursor()
		_sync_state()

func _zoom_at(world_p: Vector2, factor: float) -> void:
	var old_z: float = base_zoom * zoom_level
	zoom_level = clampf(zoom_level * factor, 0.35, 14.0)
	var new_z: float = base_zoom * zoom_level
	camera.position = world_p + (camera.position - world_p) * (old_z / new_z)
	_apply_zoom()

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / TILE), floor(p.y / TILE))

func _drag_deploy(c: Vector2i) -> void:
	if sim.state != "deploy" and sim.state != "combat":
		return
	if c == last_deploy_cell:
		return
	last_deploy_cell = c
	# 多选时按顺序循环使用已选兵种
	var kind: int = _cycle_selected_kind()
	if sim.deploy(kind, c):
		var rc := Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
		_spawn_dust(rc, COLOR_UNIT[kind], 0.8)
		deploy_cooldown = DEPLOY_INTERVAL
		_sync_state()

func _cycle_selected_kind() -> int:
	if selected_kinds.is_empty():
		selected_kinds = [Zombie.Kind.WALKER]
	var idx: int = 0
	if selected_kinds.size() > 1:
		idx = int(anim_time * 10.0) % selected_kinds.size()
	return selected_kinds[idx]

func _toggle_kind(kind: int) -> void:
	if selected_kinds.has(kind):
		if selected_kinds.size() > 1:
			selected_kinds.erase(kind)
	else:
		selected_kinds.append(kind)

func _is_kind_selected(kind: int) -> bool:
	return selected_kinds.has(kind)

func _add_waypoint(cell_center: Vector2) -> void:
	if waypoints.size() >= 5:
		waypoints.pop_front()
	waypoints.append(cell_center)
	sim.set_waypoints(waypoints)
	_spawn_ring(cell_center * TILE, Color(0.2, 0.9, 0.9, 0.7))

# 兼容旧接口：单点下兵仍可用（当前由拖拽函数覆盖）
func deploy_at(c: Vector2i) -> void:
	_drag_deploy(c)

# ===================== 基地编辑器 =====================
func _editor_place(c: Vector2i) -> void:
	var s: Vector2i = RoomDefs.size(editor_selected_type)
	var origin := Vector2i(c.x, c.y)
	if not _in_base_region(origin, s):
		return
	var id: int = grid.place(editor_selected_type, origin)
	if id >= 0:
		sim._rebuild_deploy_blocked()
		if editor_selected_type == RoomDefs.Type.COMMAND:
			sim.core_id = id
		_sync_rooms()
		fx_layer.queue_redraw()

func _editor_upgrade_under_cursor() -> void:
	var c: Vector2i = world_to_cell(get_global_mouse_position())
	if grid.occupied.has(c):
		var id: int = grid.occupied[c]
		if grid.rooms[id]["type"] == RoomDefs.Type.WALL:
			var before_hp: int = grid.rooms[id]["hp"]
			var ok: bool = sim.upgrade_wall(id)
			if ok:
				var lv: int = grid.rooms[id].get("level", 0)
				var after_hp: int = grid.rooms[id]["hp"]
				_show_toast("城墙升级 Lv%d (HP %d → %d)" % [lv + 1, before_hp, after_hp], Color(0.95, 0.75, 0.35))
				_sync_rooms()
				fx_layer.queue_redraw()
			else:
				_show_toast("城墙已满级", Color(0.9, 0.5, 0.3))
		else:
			_show_toast("只有城墙可升级", Color(0.9, 0.5, 0.3))

func _editor_remove(c: Vector2i) -> void:
	if grid.occupied.has(c):
		var id: int = grid.occupied[c]
		if id == sim.core_id:
			sim.core_id = -1
		grid.demolish(id)
		sim._rebuild_deploy_blocked()
		_sync_rooms()
		fx_layer.queue_redraw()

func _editor_clear() -> void:
	for id: int in grid.rooms.keys():
		grid.demolish(id)
	sim.core_id = -1
	sim._rebuild_deploy_blocked()
	_sync_rooms()
	fx_layer.queue_redraw()

func _in_base_region(origin: Vector2i, size: Vector2i) -> bool:
	var x0: int = BattleSim.BASE_OFFSET
	var y0: int = BattleSim.BASE_OFFSET
	var x1: int = BattleSim.BASE_OFFSET + BattleSim.BASE_REGION
	var y1: int = BattleSim.BASE_OFFSET + BattleSim.BASE_REGION
	return origin.x >= x0 and origin.y >= y0 and origin.x + size.x <= x1 and origin.y + size.y <= y1

const LAYOUT_PATH := "user://base_layout.json"

func _try_load_saved_layout() -> void:
	_load_layout_from(LAYOUT_PATH)

func _save_layout() -> void:
	var dict: Dictionary = sim.export_layout()
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(dict, "\t"))
		file.close()
		_show_toast("布局已保存", Color(0.4, 0.9, 0.4))
	else:
		_show_toast("保存失败", Color(0.9, 0.3, 0.3))

func _load_layout() -> void:
	_load_layout_from(LAYOUT_PATH)

func _load_layout_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return false
	var ok: bool = sim.load_layout(parsed)
	if ok:
		_sync_rooms()
		_sync_state()
		fx_layer.queue_redraw()
		_show_toast("布局已加载", Color(0.4, 0.9, 0.4))
	return ok

func _show_toast(text: String, col: Color) -> void:
	if hud:
		hud.show_toast(text, col)

# ===================== 主循环 =====================
func _process(delta: float) -> void:
	anim_time += delta
	if deploy_cooldown > 0.0:
		deploy_cooldown = max(0.0, deploy_cooldown - delta)
	waypoint_pulse = fmod(waypoint_pulse + delta * 2.5, TAU)
	_update_particles(delta)
	_update_bullets(delta)
	_update_floating_text(delta)
	_decay(room_flash, delta)
	_decay(turret_flash, delta)
	if core_flash > 0.0:
		core_flash = max(0.0, core_flash - delta)
	if screen_shake > 0.0:
		screen_shake = max(0.0, screen_shake - delta)
		if camera:
			var shake_str: float = screen_shake * 8.0
			camera.offset = Vector2(randf() * shake_str - shake_str * 0.5, randf() * shake_str - shake_str * 0.5)
		else:
			screen_shake = 0.0
	elif camera and camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO

	_update_turret_aim(delta)
	_sync_rooms()
	_sync_units()
	ambient_layer.update_ambient(delta)
	weather_layer.update_weather(delta)
	if sim.state == "combat" and game_mode == "attack":
		tick_acc += delta
		if tick_acc >= BattleSim.TICK:
			tick_acc -= BattleSim.TICK
			sim.tick()
			_consume_sim_events()
			_detect_state_changes()
			_sync_state()
	_update_ambient(delta)
	fx_layer.queue_redraw()
	if _shot_pending:
		_shot_frames += 1
		if _shot_frames == 14:
			var img := get_viewport().get_texture().get_image()
			if img:
				img.save_png("D:/SAFE/apocalypse/fortress/screenshot.png")
			get_tree().quit()

func _decay(d: Dictionary, delta: float) -> void:
	for k in d.keys():
		d[k] = max(0.0, float(d[k]) - delta)
		if d[k] <= 0.0:
			d.erase(k)

func _consume_sim_events() -> void:
	for ev: Dictionary in sim.fire_events:
		var f: Vector2 = ev["from"] * TILE
		var t: Vector2 = ev["to"] * TILE
		bullets.append({"from": f, "to": t, "t": 0.0, "speed": 1400.0})
		var tid: int = -1
		var bd: float = INF
		for rid: int in grid.rooms:
			if grid.rooms[rid]["type"] != RoomDefs.Type.DEFENSE:
				continue
			var rc: Vector2 = _room_center_world(grid.rooms[rid])
			var dd: float = rc.distance_to(f)
			if dd < bd:
				bd = dd; tid = rid
		if tid >= 0:
			turret_flash[tid] = 0.12
			turret_targets[tid] = ev["to"] * TILE
			if turret_nodes.has(tid):
				turret_nodes[tid].barrel.play("fire")
			# 炮口火焰与烟雾
			var muzzle: Vector2 = f + (t - f).normalized() * 28.0
			_spawn_hit_flash(muzzle, Color(1.0, 0.85, 0.35), 0.18)
			_spawn_dust(muzzle, Color(0.7, 0.7, 0.65), 0.4)
	for ev: Dictionary in sim.hit_events:
		var p: Vector2 = ev["pos"] * TILE
		var dmg: int = ev.get("dmg", BattleSim.DEFENSE_DMG)
		_spawn_blood(p, COLOR_HP_RED, 0.35)
		_spawn_spark(p, COLOR_BULLET, 0.25)
		_spawn_floating_text(p + Vector2(0, -16), "-%d" % dmg, Color(0.95, 0.35, 0.35))
	for ev: Dictionary in sim.building_hit_events:
		var p: Vector2 = ev["pos"] * TILE
		var dmg: int = ev.get("dmg", BattleSim.UNIT_DMG)
		_spawn_debris(p, Color(0.55, 0.5, 0.45), 0.35)
		_spawn_floating_text(p + Vector2(0, -22), "-%d" % dmg, Color(0.95, 0.75, 0.35))

func _detect_state_changes() -> void:
	var cur: Dictionary = {}
	for z: Zombie in sim.units:
		cur[z.id] = z.pos
		if not prev_unit_ids.has(z.id):
			_spawn_dust(z.pos * TILE, COLOR_ROCK_HI, 1.0)
		prev_unit_ids[z.id] = z.pos
	for id: int in prev_unit_ids.keys():
		if not cur.has(id):
			var p: Vector2 = prev_unit_ids[id] * TILE
			_spawn_spark(p, Color(0.5, 0.35, 0.25), 0.4)
			_spawn_dust(p, Color(0.35, 0.25, 0.2), 0.5)
			prev_unit_ids.erase(id)
	if sim.core_id >= 0 and grid.rooms.has(sim.core_id):
		var hp: int = grid.rooms[sim.core_id]["hp"]
		if prev_core_hp >= 0 and hp < prev_core_hp:
			core_flash = 0.3
			screen_shake = 0.25
			var cc := _room_center_world(grid.rooms[sim.core_id])
			_spawn_hit_flash(cc, Color(1.0, 0.6, 0.15), 0.45)
			_spawn_debris(cc, Color(0.5, 0.4, 0.3), 0.5)
		prev_core_hp = hp
	for rid: int in grid.rooms:
		var hp: int = grid.rooms[rid]["hp"]
		if prev_room_hp.has(rid) and hp < prev_room_hp[rid]:
			room_flash[rid] = 0.25
			var rc := _room_center_world(grid.rooms[rid])
			_spawn_debris(rc, Color(0.6, 0.55, 0.5), 0.3)
			_spawn_dust(rc, Color(0.45, 0.42, 0.38), 0.4)
		prev_room_hp[rid] = hp

func _update_turret_aim(delta: float) -> void:
	for rid: int in grid.rooms:
		if grid.rooms[rid]["type"] != RoomDefs.Type.DEFENSE:
			continue
		var rc := _room_center_world(grid.rooms[rid])
		var target_angle: float
		if turret_targets.has(rid):
			# 刚开火：立即指向被攻击者，随后逐渐遗忘该目标回归最近单位
			target_angle = (turret_targets[rid] - rc).angle()
		else:
			# 未开火：瞄准最近进攻单位
			var nearest: Vector2 = _nearest_unit_pos(rc)
			if nearest.distance_squared_to(rc) < INF * 0.5:
				target_angle = (nearest - rc).angle()
			else:
				target_angle = _angle_to_core(rc)
		if not turret_aim.has(rid):
			turret_aim[rid] = target_angle
		else:
			# 开火后前 0.2s 快速转向；之后慢速 idle 扫描
			var speed: float = 8.0 if turret_flash.has(rid) else 2.5
			turret_aim[rid] = _lerp_angle(turret_aim[rid], target_angle, speed * delta)
	# 清理过期目标记忆（保留 0.25s 后回归最近单位瞄准）
	for rid: int in turret_targets.keys():
		if not turret_flash.has(rid):
			turret_targets.erase(rid)

func _nearest_unit_pos(from: Vector2) -> Vector2:
	var best: float = INF
	var pos: Vector2 = Vector2.INF
	var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
	for z: Zombie in sim.units:
		var p: Vector2 = z.prev_pos.lerp(z.pos, alpha) * TILE
		var d := from.distance_squared_to(p)
		if d < best:
			best = d; pos = p
	return pos

# ===================== 精灵同步 =====================
func _make_frames(path: String, anim: String, frame_count: int, fps: float, loop: bool) -> SpriteFrames:
	var key: String = "%s|%s|%d|%.1f|%s" % [path, anim, frame_count, fps, str(loop)]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex := load(path) as Texture2D
	var fw: int = tex.get_width() / frame_count
	var fh: int = tex.get_height()
	var sf := SpriteFrames.new()
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for i: int in range(frame_count):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame(anim, at)
	_frames_cache[key] = sf
	return sf

func _make_turret_base_frames() -> SpriteFrames:
	var key := "TURRET_BASE"
	if _frames_cache.has(key):
		return _frames_cache[key]
	var cfg = TURRET_BASE_SHEET
	var sf := _make_frames(cfg.path, cfg.anim, cfg.frames, cfg.fps, true)
	_frames_cache[key] = sf
	return sf

func _make_turret_barrel_frames() -> SpriteFrames:
	var key := "TURRET_BARREL"
	if _frames_cache.has(key):
		return _frames_cache[key]
	var cfg = TURRET_BARREL_SHEET
	var tex := load(cfg.path) as Texture2D
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 1.0)
	sf.set_animation_loop("idle", true)
	var at0 := AtlasTexture.new()
	at0.atlas = tex
	at0.region = Rect2(0, 0, SPRITE_SIZE, SPRITE_SIZE)
	sf.add_frame("idle", at0)
	sf.add_animation("fire")
	sf.set_animation_speed("fire", cfg.fps)
	sf.set_animation_loop("fire", false)
	for i: int in range(cfg.frames):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE)
		sf.add_frame("fire", at)
	_frames_cache[key] = sf
	return sf

func _sync_rooms() -> void:
	for id: int in grid.rooms:
		var r: Dictionary = grid.rooms[id]
		var type: int = r["type"]
		var center: Vector2 = _room_center_world(r)
		if type == RoomDefs.Type.DEFENSE:
			if not turret_nodes.has(id):
				var pivot := Node2D.new()
				pivot.position = center
				var base := AnimatedSprite2D.new()
				base.sprite_frames = _make_turret_base_frames()
				base.play("base")
				base.position = center
				var barrel := AnimatedSprite2D.new()
				barrel.sprite_frames = _make_turret_barrel_frames()
				barrel.play("idle")
				barrel.animation_finished.connect(func(): _on_barrel_finished(id))
				pivot.add_child(barrel)
				unit_layer.add_child(base)
				unit_layer.add_child(pivot)
				turret_nodes[id] = {"pivot": pivot, "base": base, "barrel": barrel}
			else:
				turret_nodes[id].pivot.position = center
				turret_nodes[id].base.position = center
			var aim: float = float(turret_aim.get(id, 0.0))
			# 炮管精灵原图朝上（-y），故 rotation 需在数学角度上补 +PI/2 才能指向目标
			turret_nodes[id].pivot.rotation = aim + PI / 2.0
		else:
			if not room_sprites.has(id):
				var sp := AnimatedSprite2D.new()
				var cfg = ROOM_SHEETS[type]
				sp.sprite_frames = _make_frames(cfg.path, cfg.anim, cfg.frames, cfg.fps, true)
				sp.play(cfg.anim)
				sp.position = center
				unit_layer.add_child(sp)
				room_sprites[id] = sp
			else:
				room_sprites[id].position = center
		if type == RoomDefs.Type.WALL:
			var level: int = clampi(r.get("level", 0), 0, 3)
			var max_hp: int = RoomDefs.wall_hp(level)
			var ratio := float(r["hp"]) / float(max_hp)
			room_sprites[id].frame = level * 2 + (0 if ratio > 0.5 else 1)

	for id: int in room_sprites.keys():
		if not grid.rooms.has(id):
			room_sprites[id].queue_free()
			room_sprites.erase(id)
	for id: int in turret_nodes.keys():
		if not grid.rooms.has(id):
			turret_nodes[id].pivot.queue_free()
			turret_nodes[id].base.queue_free()
			turret_nodes.erase(id)

func _on_barrel_finished(id: int) -> void:
	if turret_nodes.has(id):
		var barrel: AnimatedSprite2D = turret_nodes[id].barrel
		if barrel.animation == "fire":
			barrel.play("idle")

func _sync_units() -> void:
	var cur: Dictionary = {}
	var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
	for z: Zombie in sim.units:
		cur[z.id] = true
		if not unit_sprites.has(z.id):
			var sp := AnimatedSprite2D.new()
			var path: String = ZOMBIE_SHEETS.get(z.kind, ZOMBIE_SHEETS[Zombie.Kind.WALKER])
			sp.sprite_frames = _make_frames(path, "walk", 4, 7.0, true)
			sp.play("walk")
			unit_layer.add_child(sp)
			unit_sprites[z.id] = sp
		var p: Vector2 = z.prev_pos.lerp(z.pos, alpha)
		var wp: Vector2 = p * TILE
		var sp: AnimatedSprite2D = unit_sprites[z.id]
		sp.position = wp
		var dir: Vector2 = z.pos - z.prev_pos
		if dir.length() > 0.001:
			sp.flip_h = dir.x < 0.0
	for id: int in unit_sprites.keys():
		if not cur.has(id):
			unit_sprites[id].queue_free()
			unit_sprites.erase(id)

# ===================== 粒子系统 =====================
func _spawn_spark(pos: Vector2, col: Color, life: float) -> void:
	for i in range(5):
		var a := randf() * TAU
		var sp := 40.0 + randf() * 80.0
		particles.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp,
			"life": life, "max": life, "col": col, "size": 2.5, "kind": "spark"})
	_cap_particles()

func _spawn_dust(pos: Vector2, col: Color, life: float) -> void:
	for i in range(6):
		var a := randf() * TAU
		var sp := 10.0 + randf() * 30.0
		particles.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp - Vector2(0, 10),
			"life": life, "max": life, "col": col, "size": 3.0, "kind": "dust"})
	_cap_particles()

func _spawn_hit_flash(pos: Vector2, col: Color, life: float) -> void:
	for i in range(8):
		var a := randf() * TAU
		var sp := 60.0 + randf() * 90.0
		particles.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp,
			"life": life, "max": life, "col": col, "size": 3.5, "kind": "flash"})
	_cap_particles()

func _spawn_blood(pos: Vector2, col: Color, life: float) -> void:
	for i in range(7):
		var a := randf() * TAU
		var sp := 25.0 + randf() * 55.0
		particles.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp,
			"life": life, "max": life, "col": Color(col.r, col.g, col.b, 0.85), "size": 2.8, "kind": "blood"})
	_cap_particles()

func _spawn_debris(pos: Vector2, col: Color, life: float) -> void:
	for i in range(6):
		var a := randf() * TAU
		var sp := 30.0 + randf() * 70.0
		particles.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp,
			"life": life, "max": life, "col": col, "size": 2.5, "kind": "debris"})
	_cap_particles()

func _spawn_ring(pos: Vector2, col: Color) -> void:
	particles.append({"pos": pos, "vel": Vector2.ZERO, "life": 0.4, "max": 0.4,
		"col": col, "size": TILE * 0.4, "kind": "ring"})
	_cap_particles()

func _update_particles(delta: float) -> void:
	var alive: Array = []
	for p: Dictionary in particles:
		p["life"] -= delta
		if p["life"] <= 0.0:
			continue
		p["pos"] += p["vel"] * delta
		if p["kind"] == "spark":
			p["vel"].y += 220.0 * delta
			p["vel"] *= 0.92
		elif p["kind"] == "smoke":
			p["vel"].y -= 14.0 * delta
			p["vel"] *= 0.97
		elif p["kind"] == "dust":
			p["vel"] *= 0.95
		elif p["kind"] == "flash":
			p["vel"] *= 0.85
		elif p["kind"] == "blood":
			p["vel"] *= 0.88
			p["vel"].y += 60.0 * delta
		elif p["kind"] == "debris":
			p["vel"].y += 180.0 * delta
			p["vel"] *= 0.92
		alive.append(p)
	particles = alive

func _update_bullets(delta: float) -> void:
	var alive: Array = []
	for b: Dictionary in bullets:
		var dist: float = b["from"].distance_to(b["to"])
		var step: float = b["speed"] * delta / max(dist, 1.0)
		b["t"] += step
		if b["t"] >= 1.0:
			_spawn_spark(b["to"], COLOR_BULLET, 0.18)
			continue
		alive.append(b)
	bullets = alive

func _update_ambient(delta: float) -> void:
	for rid: int in grid.rooms:
		if grid.rooms[rid]["type"] != RoomDefs.Type.PRODUCTION:
			continue
		if not smoke_acc.has(rid):
			smoke_acc[rid] = 0.0
		smoke_acc[rid] -= delta
		if smoke_acc[rid] <= 0.0:
			smoke_acc[rid] = 0.5
			var r: Dictionary = grid.rooms[rid]
			var pos := _room_center_world(r) + Vector2(TILE * 0.2, -TILE * 0.3)
			particles.append({"pos": pos, "vel": Vector2(randf() * 10.0 - 5.0, -26.0),
				"life": 1.2, "max": 1.2, "col": Color(0.55, 0.55, 0.55, 0.5), "size": 4.0, "kind": "smoke"})
	_cap_particles()
	dust_acc += delta
	if dust_acc > 0.25:
		dust_acc = 0.0
		var W := grid.size * TILE
		var pos := Vector2(randf() * W, randf() * W)
		particles.append({"pos": pos, "vel": Vector2(randf() * 6.0 - 3.0, randf() * 6.0 - 3.0),
			"life": 2.0, "max": 2.0, "col": Color(0.6, 0.55, 0.5, 0.25), "size": 1.5, "kind": "dust"})
	_cap_particles()

func _spawn_floating_text(pos: Vector2, text: String, col: Color) -> void:
	floating_text.append({"pos": pos, "text": text, "col": col, "life": 1.0, "max": 1.0, "vy": -40.0})
	if floating_text.size() > 40:
		floating_text.pop_front()

func _update_floating_text(delta: float) -> void:
	var alive: Array = []
	for t: Dictionary in floating_text:
		t["life"] -= delta
		if t["life"] <= 0.0:
			continue
		t["pos"].y += t["vy"] * delta
		t["vy"] += 20.0 * delta
		alive.append(t)
	floating_text = alive

func _cap_particles() -> void:
	if particles.size() > 500:
		particles = particles.slice(particles.size() - 500)

# ===================== 工具 =====================
func _room_center_world(r: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for c in r["cells"]:
		sum += Vector2(c.x + 0.5, c.y + 0.5)
	return sum / r["cells"].size() * TILE

func _angle_to_core(from: Vector2) -> float:
	return (Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0) - from).angle()

func _lerp_angle(a: float, b: float, t: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	elif d < -PI:
		d += TAU
	return a + d * t

func _hash(n: float) -> float:
	var s := sin(n * 12.9898) * 43758.5453
	return s - floor(s)

func _sync_state() -> void:
	update_hud()
	fx_layer.queue_redraw()

func update_hud() -> void:
	if hud:
		var wn: String = weather_layer.weather_name() if weather_layer else "晴朗"
		hud.set_state(sim.state, sim.army, sim.units.size(), sim.army_total, selected_kinds, game_mode, editor_selected_type, wn)

# ===================== 开发期截图 =====================
func _dev_shot_setup() -> void:
	_cancel_intro()
	weather_layer.set_weather("rain")
	_sync_state()
	camera.zoom = Vector2(base_zoom * 3.5, base_zoom * 3.5)
	camera.position = _grid_center_world()
	# 开发截图：给默认基地外加一圈示例城墙（仅用于截图展示），部队从外围下兵
	var mid := int(BattleSim.BASE_OFFSET + BattleSim.BASE_REGION / 2)
	var wl := mid - BattleSim.WALL_HALF
	var wh := mid + BattleSim.WALL_HALF - 1
	for x in range(wl, wh + 1):
		grid.place(RoomDefs.Type.WALL, Vector2i(x, wl), 1)
		grid.place(RoomDefs.Type.WALL, Vector2i(x, wh), 2)
	for y in range(wl + 1, wh):
		grid.place(RoomDefs.Type.WALL, Vector2i(wl, y), 0)
		grid.place(RoomDefs.Type.WALL, Vector2i(wh, y), 3)
	sim._rebuild_deploy_blocked()
	_sync_rooms()
	# 包围盒外扩 2 格（笼罩范围=墙外 1 格，故最近合法下兵点是外墙外 2 格）
	var lo := wl - 2
	var hi := wh + 2
	var cells: Array = []
	for x in range(lo, hi + 1):
		cells.append(Vector2i(x, lo))
		cells.append(Vector2i(x, hi))
	for y in range(lo + 1, hi):
		cells.append(Vector2i(lo, y))
		cells.append(Vector2i(hi, y))
	var order := [Zombie.Kind.WALKER, Zombie.Kind.RUNNER, Zombie.Kind.SPITTER]
	var ci := 0
	for k in order:
		while sim.army[k] > 0 and ci < cells.size():
			if sim.deploy(k, cells[ci]):
				ci += 1
	for i in range(60):
		sim.tick()
		_consume_sim_events()
		_detect_state_changes()
		_sync_units()
		if sim.state != "combat":
			break
	RenderingServer.viewport_set_update_mode(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_shot_pending = true

# 屏幕右下角废墟贴花：遮挡生成图水印并融入场景
class CornerDecalLayer extends Control:
	var main: Node

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var vp: Vector2 = get_viewport_rect().size
		# 贴花区域：右下角，覆盖常见水印位置
		var w: float = 420.0
		var h: float = 160.0
		var x0: float = vp.x - w
		var y0: float = vp.y - h
		# 主暗区：不规则多边形，地面污渍/烧焦痕迹
		var pts := PackedVector2Array([
			Vector2(vp.x, vp.y - h * 0.2),
			Vector2(vp.x, vp.y),
			Vector2(vp.x - w * 0.85, vp.y),
			Vector2(vp.x - w, vp.y - h * 0.35),
			Vector2(vp.x - w * 0.9, vp.y - h * 0.75),
			Vector2(vp.x - w * 0.45, vp.y - h * 0.95),
			Vector2(vp.x - w * 0.15, vp.y - h * 0.8),
		])
		draw_colored_polygon(pts, Color(0.12, 0.10, 0.09, 0.82))
		# 内层较亮污渍，增加层次
		var inner := PackedVector2Array([
			Vector2(vp.x - 40, vp.y - 40),
			Vector2(vp.x - 20, vp.y - 100),
			Vector2(vp.x - 160, vp.y - 120),
			Vector2(vp.x - 280, vp.y - 90),
			Vector2(vp.x - 300, vp.y - 30),
			Vector2(vp.x - 180, vp.y - 20),
		])
		draw_colored_polygon(inner, Color(0.18, 0.15, 0.13, 0.55))
		# 碎石/瓦砾：随机分布的小椭圆
		var rng := RandomNumberGenerator.new()
		rng.seed = 72631
		for i: int in range(60):
			var px: float = x0 + rng.randf() * w
			var py: float = y0 + rng.randf() * h
			var rr: float = 2.0 + rng.randf() * 6.0
			var c: Color = Color(0.22 + rng.randf()*0.08, 0.19 + rng.randf()*0.07, 0.16 + rng.randf()*0.06, 0.55 + rng.randf()*0.25)
			draw_circle(Vector2(px, py), rr, c)
		# 裂缝
		for i: int in range(8):
			var sx: float = x0 + 30 + rng.randf() * (w - 60)
			var sy: float = y0 + 20 + rng.randf() * (h - 40)
			var ex: float = sx + (rng.randf() - 0.5) * 90.0
			var ey: float = sy + (rng.randf() - 0.5) * 50.0
			draw_line(Vector2(sx, sy), Vector2(ex, ey), Color(0.05, 0.04, 0.04, 0.5), 1.5)
		# 废弃轮胎/油桶轮廓（俯视）
		draw_circle(Vector2(vp.x - 90, vp.y - 75), 22, Color(0.10, 0.09, 0.08, 0.75))
		draw_circle(Vector2(vp.x - 90, vp.y - 75), 14, Color(0.16, 0.14, 0.12, 0.55))
		draw_circle(Vector2(vp.x - 150, vp.y - 60), 16, Color(0.10, 0.09, 0.08, 0.70))
		draw_circle(Vector2(vp.x - 150, vp.y - 60), 9, Color(0.16, 0.14, 0.12, 0.50))
		# 锈迹斑块
		draw_circle(Vector2(vp.x - 240, vp.y - 95), 35, Color(0.34, 0.20, 0.14, 0.28))
		draw_circle(Vector2(vp.x - 320, vp.y - 55), 28, Color(0.30, 0.18, 0.13, 0.22))

# ===================== 内部分层节点 =====================
class BGLayer extends Node2D:
	var main: Node

	func _draw() -> void:
		_draw_mountain()

	func _draw_mountain() -> void:
		var grid: GridModel = main.grid
		var W := grid.size * TILE
		# 稀疏网格：每 5 格一条淡线，标识战场边界与中线，不压过彩绘地图
		for i in range(0, grid.size + 1, 5):
			var is_border: bool = (i == 0 or i == grid.size or i == grid.size / 2)
			var col := Color(0.45, 0.42, 0.38, 0.28 if is_border else 0.16)
			var w: float = 2.0 if is_border else 1.0
			draw_line(Vector2(i * TILE, 0), Vector2(i * TILE, W), col, w)
			draw_line(Vector2(0, i * TILE), Vector2(W, i * TILE), col, w)
		# 核心光晕（轻微，不遮挡背景细节）
		var cc := Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0)
		for r in range(4, 0, -1):
			var a := 0.05 * (r / 4.0)
			draw_circle(cc, float(r) * TILE * 0.6, Color(0.91, 0.57, 0.24, a))


class FXLayer extends Node2D:
	var main: Node

	func _draw() -> void:
		_draw_hp_bars()
		_draw_flashes()
		_draw_waypoints()
		_draw_deploy_preview()
		_draw_editor_preview()
		_draw_bullets()
		_draw_particles()
		_draw_floating_text()

	func _draw_hp_bars() -> void:
		var grid: GridModel = main.grid
		var sim: BattleSim = main.sim
		var tick_acc: float = main.tick_acc
		var room_flash: Dictionary = main.room_flash
		for id: int in grid.rooms:
			var r: Dictionary = grid.rooms[id]
			var max_hp: int = RoomDefs.hp(r["type"])
			if r["type"] == RoomDefs.Type.WALL:
				max_hp = RoomDefs.wall_hp(r.get("level", 0))
			if r["hp"] < max_hp:
				var origin := Vector2(r["origin"].x * TILE + 2.0, r["origin"].y * TILE - 11.0)
				var flash: float = room_flash.get(id, 0.0)
				_draw_hp_bar(origin, RoomDefs.size(r["type"]).x * TILE - 4.0, r["hp"], max_hp, flash)
		var zr := TILE * 0.26
		for z: Zombie in sim.units:
			if z.hp < z.max_hp:
				var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
				var p: Vector2 = z.prev_pos.lerp(z.pos, alpha)
				var wp: Vector2 = p * TILE
				var flash: float = 1.0 if (z.max_hp - z.hp > 0 and z.hp < z.max_hp * 0.25 and int(main.anim_time * 10.0) % 2 == 0) else 0.0
				_draw_hp_bar(wp - Vector2(zr, zr + 14), zr * 2.0, z.hp, z.max_hp, flash)

	func _draw_hp_bar(origin: Vector2, width: float, hp: int, max_hp: int, flash: float = 0.0) -> void:
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_h := HP_BAR_H
		var full_rect := Rect2(origin - Vector2(HP_BAR_BORDER, HP_BAR_BORDER),
			Vector2(width + HP_BAR_BORDER * 2.0, bar_h + HP_BAR_BORDER * 2.0))
		# 外边框
		draw_rect(full_rect, COLOR_HP_BORDER)
		# 暗底
		draw_rect(Rect2(origin, Vector2(width, bar_h)), COLOR_HP_DARK)
		# 分段渐变填充
		var col := COLOR_HP_GREEN if ratio > 0.6 else (COLOR_HP_ORANGE if ratio > 0.3 else COLOR_HP_RED)
		if flash > 0.0 and int(main.anim_time * 12.0) % 2 == 0:
			col = COLOR_HP_FLASH
		var fill_w := width * ratio
		draw_rect(Rect2(origin, Vector2(fill_w, bar_h)), col)
		# 分段线
		var seg_w := width / float(HP_BAR_SEGMENTS)
		for i: int in range(1, HP_BAR_SEGMENTS):
			var x := origin.x + seg_w * i
			draw_line(Vector2(x, origin.y), Vector2(x, origin.y + bar_h), COLOR_HP_BORDER, 1.0)
		# 高光细线
		draw_line(origin, origin + Vector2(fill_w, 0), Color(1, 1, 1, 0.4), 1.0)

	func _draw_flashes() -> void:
		var grid: GridModel = main.grid
		var sim: BattleSim = main.sim
		var core_flash: float = main.core_flash
		if core_flash > 0.0 and sim.core_id >= 0 and grid.rooms.has(sim.core_id):
			var r: Dictionary = grid.rooms[sim.core_id]
			var sz: Vector2i = RoomDefs.size(RoomDefs.Type.COMMAND)
			var rect := Rect2(Vector2(r["origin"].x * TILE, r["origin"].y * TILE), Vector2(sz.x * TILE, sz.y * TILE))
			draw_rect(rect, Color(1, 0.3, 0.3, 0.5 * (core_flash / 0.3)))
		var room_flash: Dictionary = main.room_flash
		for id: int in room_flash:
			if grid.rooms.has(id):
				var r: Dictionary = grid.rooms[id]
				var sz: Vector2i = RoomDefs.size(r["type"])
				var rect := Rect2(Vector2(r["origin"].x * TILE, r["origin"].y * TILE), Vector2(sz.x * TILE, sz.y * TILE))
				draw_rect(rect, Color(1, 1, 1, 0.5 * (room_flash[id] / 0.3)))

	func _draw_deploy_preview() -> void:
		if main.game_mode != "attack":
			return
		var grid: GridModel = main.grid
		var sim: BattleSim = main.sim
		if sim.state != "deploy" and sim.state != "combat":
			return
		var c: Vector2i = main.world_to_cell(get_global_mouse_position())
		if c.x < 0 or c.y < 0 or c.x >= grid.size or c.y >= grid.size:
			return
		var ok: bool = (not grid.occupied.has(c)) and (not sim.blocked_deploy.has(c))
		var col: Color = main.COLOR_DEPLOY_OK if ok else main.COLOR_DEPLOY_BAD
		var rect := Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(TILE, TILE))
		draw_rect(rect, col)
		var cx := c.x * TILE + TILE / 2.0
		var cy := c.y * TILE + TILE / 2.0
		# 多选时画叠加小圆表示多个兵种
		if main.selected_kinds.size() == 1:
			draw_circle(Vector2(cx, cy), TILE * 0.28, main.COLOR_UNIT[main.selected_kinds[0]])
			draw_arc(Vector2(cx, cy), TILE * 0.28, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 2.0)
		else:
			for i: int in range(main.selected_kinds.size()):
				var ang: float = TAU * i / main.selected_kinds.size() + main.anim_time * 2.0
				var pp: Vector2 = Vector2(cx + cos(ang) * TILE * 0.18, cy + sin(ang) * TILE * 0.18)
				draw_circle(pp, TILE * 0.12, main.COLOR_UNIT[main.selected_kinds[i]])

	func _draw_waypoints() -> void:
		if main.game_mode != "attack" or main.waypoints.is_empty():
			return
		for i: int in range(main.waypoints.size()):
			var wp: Vector2 = main.waypoints[i]
			var pos: Vector2 = wp * TILE
			var pulse: float = 1.0 + sin(main.waypoint_pulse + i * 0.8) * 0.18
			draw_circle(pos, TILE * 0.35 * pulse, Color(0.2, 0.95, 0.95, 0.35))
			draw_arc(pos, TILE * 0.35 * pulse, 0.0, TAU, 24, Color(0.2, 0.95, 0.95, 0.9), 2.5)
		# 连线
		for i: int in range(main.waypoints.size() - 1):
			draw_line(main.waypoints[i] * TILE, main.waypoints[i + 1] * TILE, Color(0.2, 0.95, 0.95, 0.5), 2.0)

	func _draw_editor_preview() -> void:
		if main.game_mode != "editor":
			return
		var grid: GridModel = main.grid
		var c: Vector2i = main.world_to_cell(get_global_mouse_position())
		var s: Vector2i = RoomDefs.size(main.editor_selected_type)
		var ok: bool = main._in_base_region(c, s) and grid.can_place(main.editor_selected_type, c)
		var col: Color = main.COLOR_DEPLOY_OK if ok else main.COLOR_DEPLOY_BAD
		var rect := Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(s.x * TILE, s.y * TILE))
		draw_rect(rect, col)
		# 半透明填充房间主题色
		var theme: Color = RoomDefs.color(main.editor_selected_type)
		theme.a = 0.35
		draw_rect(rect, theme)
		# 悬停显示现有城墙等级/HP
		if grid.occupied.has(c):
			var id: int = grid.occupied[c]
			var r: Dictionary = grid.rooms[id]
			var lv: int = r.get("level", 0)
			var txt: String = ""
			if r["type"] == RoomDefs.Type.WALL:
				var max_hp: int = RoomDefs.wall_hp(lv)
				txt = "城墙 Lv%d  HP %d/%d" % [lv + 1, r["hp"], max_hp]
			else:
				txt = "%s HP %d/%d" % [RoomDefs.symbol(r["type"]), r["hp"], RoomDefs.hp(r["type"])]
			var font: Font = ThemeDB.fallback_font
			var pos := Vector2(c.x * TILE + 4, c.y * TILE - 8)
			draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.8))
			draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.92, 0.75))

	func _draw_bullets() -> void:
		for b: Dictionary in main.bullets:
			var cur: Vector2 = b["from"].lerp(b["to"], b["t"])
			draw_line(b["from"], cur, COLOR_BULLET, 2.5)
			draw_circle(cur, 3.5, COLOR_BULLET)
			draw_circle(cur, 1.8, Color(1, 1, 1, 0.95))

	func _draw_particles() -> void:
		for p: Dictionary in main.particles:
			var life: float = p["life"] / p["max"]
			var col: Color = p["col"]
			col.a *= clamp(life, 0.0, 1.0)
			match p["kind"]:
				"ring":
					var rr: float = p["size"] * (1.4 - life)
					draw_arc(p["pos"], rr, 0.0, TAU, 24, col, 2.5)
				"smoke":
					draw_circle(p["pos"], p["size"] * (1.6 - life), col)
				"blood":
					draw_circle(p["pos"], p["size"] * (0.6 + life * 0.6), col)
				"debris":
					var s: float = p["size"] * clamp(life, 0.3, 1.0)
					draw_rect(Rect2(p["pos"] - Vector2(s, s) * 0.5, Vector2(s, s)), col)
				_:
					draw_circle(p["pos"], p["size"] * clamp(life, 0.2, 1.0), col)

	func _draw_floating_text() -> void:
		var font: Font = ThemeDB.fallback_font
		for t: Dictionary in main.floating_text:
			var life: float = t["life"] / t["max"]
			var col: Color = t["col"]
			col.a = clamp(life, 0.0, 1.0)
			var pos: Vector2 = t["pos"]
			# 粗描边效果：先画黑底字偏移
			for off: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				draw_string(font, pos + off, t["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0, 0, 0, col.a))
			draw_string(font, pos, t["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 18, col)


# ===================== 环境动态层：游荡僵尸、飞鸟 =====================
class AmbientLayer extends Node2D:
	var main: Node
	var ambient_zombies: Array = []
	var birds: Array = []
	const AMBIENT_COUNT := 12
	const BIRD_COUNT := 8
	const AVOID_RANGE := 120.0

	func spawn_ambient() -> void:
		var W: float = float(main.grid.size) * main.TILE
		for i: int in range(AMBIENT_COUNT):
			# 主要生成在外围非基地区域
			var edge: bool = randf() < 0.7
			var pos: Vector2
			if edge:
				var side: int = randi() % 4
				match side:
					0: pos = Vector2(randf() * W, randf() * W * 0.15)
					1: pos = Vector2(randf() * W, W * 0.85 + randf() * W * 0.15)
					2: pos = Vector2(randf() * W * 0.15, randf() * W)
					3: pos = Vector2(W * 0.85 + randf() * W * 0.15, randf() * W)
			else:
				pos = Vector2(randf() * W, randf() * W)
			ambient_zombies.append({
				"pos": pos,
				"vel": Vector2(randf() * 20.0 - 10.0, randf() * 20.0 - 10.0),
				"anim": randf() * 10.0,
				"tint": Color(0.45, 0.55, 0.35, 0.75),
			})
		for i: int in range(BIRD_COUNT):
			var y: float = 80.0 + randf() * (W - 160.0)
			var dir: float = 1.0 if randf() < 0.5 else -1.0
			birds.append({
				"pos": Vector2(-60.0 if dir > 0 else W + 60.0, y),
				"vel": Vector2(dir * (60.0 + randf() * 40.0), randf() * 10.0 - 5.0),
				"wing": randf() * TAU,
			})

	func update_ambient(delta: float) -> void:
		var W: float = float(main.grid.size) * main.TILE
		# 环境僵尸：慢速游荡 + 躲避附近战斗单位
		for z: Dictionary in ambient_zombies:
			z["anim"] += delta * 3.0
			# 寻找附近进攻单位并躲避
			var flee := Vector2.ZERO
			for u: Zombie in main.sim.units:
				var up: Vector2 = u.pos * main.TILE
				var d: Vector2 = up - z["pos"]
				if d.length() < AVOID_RANGE:
					flee -= d.normalized() * (AVOID_RANGE - d.length()) * 4.0
			z["vel"] += flee * delta
			z["vel"] = z["vel"].limit_length(22.0)
			z["pos"] += z["vel"] * delta
			# 边界环绕
			if z["pos"].x < -40: z["pos"].x = W + 40
			if z["pos"].x > W + 40: z["pos"].x = -40
			if z["pos"].y < -40: z["pos"].y = W + 40
			if z["pos"].y > W + 40: z["pos"].y = -40
		# 鸟群：直线飞越 + 轻微正弦波动
		for b: Dictionary in birds:
			b["wing"] += delta * 12.0
			b["pos"] += b["vel"] * delta
			b["pos"].y += sin(b["pos"].x * 0.01 + b["wing"] * 0.3) * 8.0 * delta
			if b["vel"].x > 0 and b["pos"].x > W + 80:
				b["pos"].x = -80
				b["pos"].y = 80.0 + randf() * (W - 160.0)
			elif b["vel"].x < 0 and b["pos"].x < -80:
				b["pos"].x = W + 80
				b["pos"].y = 80.0 + randf() * (W - 160.0)
		queue_redraw()

	func _draw() -> void:
		_draw_ambient_zombies()
		_draw_birds()

	func _draw_ambient_zombies() -> void:
		for z: Dictionary in ambient_zombies:
			var pos: Vector2 = z["pos"]
			var walk: float = sin(z["anim"])
			var body_off := Vector2(walk * 1.5, 0)
			var leg1 := Vector2(-3 + walk * 2.0, 8)
			var leg2 := Vector2(3 - walk * 2.0, 8)
			var col: Color = z["tint"]
			# 头
			draw_circle(pos + Vector2(0, -6), 4.5, col)
			# 躯干
			draw_rect(Rect2(pos + Vector2(-4, -2) + body_off, Vector2(8, 10)), col)
			# 腿
			draw_line(pos + Vector2(-2, 6), pos + leg1, col, 2.0)
			draw_line(pos + Vector2(2, 6), pos + leg2, col, 2.0)
			# 前伸手臂
			draw_line(pos + Vector2(0, 0), pos + Vector2(6 + walk, 2), col, 2.0)

	func _draw_birds() -> void:
		for b: Dictionary in birds:
			var pos: Vector2 = b["pos"]
			var wing: float = sin(b["wing"]) * 5.0
			var c: Color = Color(0.2, 0.22, 0.24, 0.85)
			draw_line(pos + Vector2(-6, -wing), pos, c, 1.5)
			draw_line(pos + Vector2(6, -wing), pos, c, 1.5)
			draw_circle(pos, 1.5, c)


# ===================== 天气层：雨 / 雪 =====================
class WeatherLayer extends Node2D:
	var main: Node
	var weather: String = "clear"
	var particles: Array = []
	var acc: float = 0.0
	const DENSITY := {
		"rain": 900,
		"snow": 500,
		"clear": 0,
	}
	const SPEED := {
		"rain": Vector2(-120.0, 720.0),
		"snow": Vector2(-30.0, 90.0),
	}

	func set_weather(state: String) -> void:
		weather = state
		particles.clear()
		acc = 0.0

	func weather_name() -> String:
		match weather:
			"rain": return "雨天"
			"snow": return "雪天"
			_: return "晴朗"

	func update_weather(delta: float) -> void:
		if weather == "clear":
			particles.clear()
			return
		var cam: Camera2D = main.camera
		if cam == null:
			return
		# 在相机视野附近生成粒子
		var view: Vector2 = get_viewport_rect().size / cam.zoom
		var center: Vector2 = cam.position
		var target: int = DENSITY.get(weather, 0)
		var spawn_rate: float = float(target) * 0.6
		acc += delta
		while acc > 0.03 and particles.size() < target:
			acc -= 0.03
			var p := Vector2(
				center.x - view.x * 0.6 + randf() * view.x * 1.2,
				center.y - view.y * 0.6 + randf() * view.y * 1.2
			)
			particles.append({"pos": p, "life": 1.0 + randf() * 0.5})
		var sp: Vector2 = SPEED.get(weather, Vector2.ZERO)
		var alive: Array = []
		for p: Dictionary in particles:
			p["pos"] += sp * delta
			p["pos"].x += sin(p["pos"].y * 0.02 + p["life"] * 5.0) * (10.0 if weather == "snow" else 0.0) * delta
			p["life"] -= delta
			if p["life"] > 0.0 and p["pos"].y < center.y + view.y * 0.7:
				alive.append(p)
		particles = alive
		queue_redraw()

	func _draw() -> void:
		match weather:
			"rain":
				for p: Dictionary in particles:
					draw_line(p["pos"], p["pos"] + Vector2(-8, 38), Color(0.9, 0.93, 1.0, 0.88), 2.5)
					# 雨滴头部高光
					draw_circle(p["pos"] + Vector2(-8, 38), 1.6, Color(1.0, 1.0, 1.0, 0.55))
			"snow":
				for p: Dictionary in particles:
					var life: float = p["life"]
					var a: float = clamp(life * 0.8, 0.0, 1.0)
					draw_circle(p["pos"], 1.6, Color(0.95, 0.97, 1.0, a * 0.7))
