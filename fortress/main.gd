extends Node2D

# Phase 4 垂直切片：建造 + 波次最小闭环（build → defend → expand）
# 渲染/输入翻译层：逻辑全部在 core/（服务端可移植），本脚本只做输入翻译与矢量风格渲染。

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Zombie := preload("res://core/zombie.gd")
const HUD := preload("res://hud.gd")

const TILE := 48          # 单元格像素（比之前 32 更大，可读性更好）
const MARGIN := 1.08      # 相机留边距

const COLOR_BG := Color(0.09, 0.10, 0.11)
const COLOR_GRID := Color(0.22, 0.23, 0.25)
const COLOR_GRID_STRONG := Color(0.30, 0.31, 0.34)
const COLOR_HOVER_OK := Color(0.30, 0.75, 0.40, 0.35)
const COLOR_HOVER_BAD := Color(0.90, 0.25, 0.25, 0.40)
const COLOR_HP_BG := Color(0.15, 0.15, 0.15)
const COLOR_HP_GREEN := Color(0.30, 0.80, 0.35)
const COLOR_HP_ORANGE := Color(0.91, 0.57, 0.24)
const COLOR_HP_RED := Color(0.85, 0.25, 0.25)
const COLOR_ZOMBIE := {
	Zombie.Kind.WALKER: Color(0.91, 0.57, 0.24),
	Zombie.Kind.RUNNER: Color(0.85, 0.28, 0.28),
	Zombie.Kind.SPITTER: Color(0.70, 0.30, 0.75),
}

@onready var hud: HUD = $HUD

var grid: GridModel
var sim: BattleSim
var selected_type: int = RoomDefs.Type.DEFENSE
var tick_acc: float = 0.0
var camera: Camera2D

func _ready() -> void:
	grid = GridModel.new()
	grid.set_level(1)
	var center := Vector2i(grid.size / 2 - 1, grid.size / 2 - 1)
	var cid := grid.place(RoomDefs.Type.COMMAND, center)
	if cid >= 0:
		grid.rooms[cid]["hp"] = RoomDefs.hp(RoomDefs.Type.COMMAND)
	sim = BattleSim.new(grid)
	_setup_camera()
	_sync_state()

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.position = _grid_center_world()
	add_child(camera)
	camera.make_current()
	_rezoom()
	get_tree().root.size_changed.connect(_rezoom)

func _rezoom() -> void:
	if camera == null:
		return
	var vp := get_viewport_rect().size
	var world_px := grid.size * TILE
	var z: float = min(vp.x, vp.y) / (world_px * MARGIN)
	camera.zoom = Vector2(z, z)

func _grid_center_world() -> Vector2:
	return Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if sim.state == "build":
				try_place(world_to_cell(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if sim.state == "build":
				_demolish_at_cell(world_to_cell(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: selected_type = RoomDefs.Type.WALL
			KEY_2: selected_type = RoomDefs.Type.DEFENSE
			KEY_3: selected_type = RoomDefs.Type.PRODUCTION
			KEY_X, KEY_DELETE: _demolish_at_mouse()
			KEY_U: _upgrade_at_mouse()
			KEY_SPACE: start_wave()
		_sync_state()

func _pick_room_id() -> int:
	var c: Vector2i = world_to_cell(get_global_mouse_position())
	return grid.occupied.get(c, -1)

func _demolish_at_cell(c: Vector2i) -> void:
	var id: int = grid.occupied.get(c, -1)
	if id < 0:
		return
	var refund: int = sim.try_demolish(id)
	if refund >= 0:
		_sync_state()

func _demolish_at_mouse() -> void:
	_demolish_at_cell(world_to_cell(get_global_mouse_position()))

func _upgrade_at_mouse() -> void:
	var id: int = _pick_room_id()
	if id < 0:
		return
	var new_hp: int = sim.try_upgrade(id)
	if new_hp >= 0:
		_sync_state()

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / TILE), floor(p.y / TILE))

func try_place(c: Vector2i) -> void:
	var id: int = sim.try_place(selected_type, c)
	if id >= 0:
		grid.rooms[id]["hp"] = RoomDefs.hp(selected_type)
		_sync_state()

func start_wave() -> void:
	if sim.state != "build":
		return
	sim.begin_wave(sim.wave + 1)
	tick_acc = 0.0
	_sync_state()

func _process(delta: float) -> void:
	var changed := false
	if sim.state == "combat":
		tick_acc += delta
		if tick_acc >= BattleSim.TICK:
			tick_acc -= BattleSim.TICK
			sim.tick()
			changed = true
			_sync_state()
			if sim.state != "combat":
				return
		queue_redraw()
	else:
		queue_redraw()
	if changed:
		_sync_state()

func _draw() -> void:
	_draw_background()
	_draw_grid()
	_draw_rooms()
	_draw_hover_preview()
	_draw_zombies()

func _draw_background() -> void:
	var world_px := grid.size * TILE
	draw_rect(Rect2(Vector2.ZERO, Vector2(world_px, world_px)), COLOR_BG)
	# 棋盘格地面：让空地块有层次，不像纯灰板
	var light := Color(0.11, 0.12, 0.13)
	var dark := Color(0.095, 0.105, 0.115)
	for x in range(grid.size):
		for y in range(grid.size):
			var col := light if (x + y) % 2 == 0 else dark
			draw_rect(Rect2(Vector2(x * TILE, y * TILE), Vector2(TILE, TILE)), col)

func _draw_grid() -> void:
	var world_px := grid.size * TILE
	for i in range(grid.size + 1):
		var col := COLOR_GRID_STRONG if i % 3 == 0 else COLOR_GRID
		draw_line(Vector2(i * TILE, 0), Vector2(i * TILE, world_px), col, 1.5 if i % 3 == 0 else 1.0)
		draw_line(Vector2(0, i * TILE), Vector2(world_px, i * TILE), col, 1.5 if i % 3 == 0 else 1.0)

func _draw_rooms() -> void:
	for id in grid.rooms:
		var r: Dictionary = grid.rooms[id]
		var type: int = r["type"]
		var origin: Vector2i = r["origin"]
		var sz: Vector2i = RoomDefs.size(type)
		var rect := Rect2(Vector2(origin.x * TILE, origin.y * TILE), Vector2(sz.x * TILE, sz.y * TILE))

		# 主体色块
		var base_col := RoomDefs.color(type)
		var top_col := base_col.lightened(0.12)
		var bot_col := base_col.darkened(0.15)
		draw_rect(rect, base_col)

		# 墙体：画几道砖缝，避免纯色块
		if type == RoomDefs.Type.WALL:
			var brick := bot_col.darkened(0.2)
			for i in range(1, 3):
				var yy := rect.position.y + rect.size.y * i / 3.0
				draw_line(Vector2(rect.position.x + 2, yy), Vector2(rect.position.x + rect.size.x - 2, yy), brick, 1.0)

		# 指挥核心：内部高光，显得有能量感
		if type == RoomDefs.Type.COMMAND:
			var glow := base_col.lightened(0.25)
			glow.a = 0.35
			draw_rect(Rect2(rect.position + rect.size * 0.15, rect.size * 0.7), glow)

		# 顶部高光边
		draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), top_col, 2.0)
		draw_line(rect.position, rect.position + Vector2(0, rect.size.y), top_col, 2.0)
		# 底部阴影边
		draw_line(rect.position + Vector2(0, rect.size.y), rect.position + rect.size, bot_col, 2.0)
		draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, bot_col, 2.0)

		# 房间图标 / 符号（按字体基线居中）
		var symbol: String = RoomDefs.symbol(type)
		var font := ThemeDB.fallback_font
		var font_size := int(min(rect.size.x, rect.size.y) * 0.55)
		var text_size := font.get_string_size(symbol, font_size)
		var ascent := font.get_ascent(font_size)
		var descent := font.get_descent(font_size)
		var text_h := ascent + descent
		var text_pos := Vector2(
			rect.position.x + (rect.size.x - text_size.x) / 2.0,
			rect.position.y + (rect.size.y + text_h) / 2.0 - descent
		)
		draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))

		# HP 条（受损时显示）
		if r.has("hp") and r["hp"] < RoomDefs.hp(type):
			_draw_hp_bar(rect.position + Vector2(2, -10), rect.size.x - 4, r["hp"], RoomDefs.hp(type))

func _draw_hp_bar(origin: Vector2, width: float, hp: int, max_hp: int) -> void:
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var bar_h := 6.0
	draw_rect(Rect2(origin, Vector2(width, bar_h)), COLOR_HP_BG)
	var col := COLOR_HP_GREEN if ratio > 0.6 else (COLOR_HP_ORANGE if ratio > 0.3 else COLOR_HP_RED)
	draw_rect(Rect2(origin, Vector2(width * ratio, bar_h)), col)

func _draw_hover_preview() -> void:
	if sim.state != "build":
		return
	var c: Vector2i = world_to_cell(get_global_mouse_position())
	if c.x < 0 or c.y < 0 or c.x >= grid.size or c.y >= grid.size:
		return

	# 若悬停已有防御塔，显示射程圈
	var hover_id: int = grid.occupied.get(c, -1)
	if hover_id >= 0 and grid.rooms[hover_id]["type"] == RoomDefs.Type.DEFENSE:
		var center := Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
		var radius := BattleSim.DEFENSE_RANGE_CELLS * TILE
		draw_circle(center, radius, Color(0.20, 0.58, 0.82, 0.08))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.20, 0.58, 0.82, 0.35), 1.5)

	# 放置防御塔时，同时预览射程圈
	if selected_type == RoomDefs.Type.DEFENSE:
		var center := Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
		var radius := BattleSim.DEFENSE_RANGE_CELLS * TILE
		draw_circle(center, radius, Color(0.20, 0.58, 0.82, 0.10))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.20, 0.58, 0.82, 0.40), 1.5)

	# 放置预览
	var sz: Vector2i = RoomDefs.size(selected_type)
	var rect := Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(sz.x * TILE, sz.y * TILE))
	var cost: int = BattleSim.ROOM_COST.get(selected_type, 20)
	var affordable := sim.scrap >= cost
	var fits := grid.can_place(selected_type, c)
	var ok := affordable and fits and sim.state == "build"
	draw_rect(rect, COLOR_HOVER_OK if ok else COLOR_HOVER_BAD)
	# 虚线边框
	var dash_len := 6.0
	var perimeter := 2.0 * (rect.size.x + rect.size.y)
	if perimeter > 0:
		var segs := int(perimeter / (dash_len * 2.0))
		for i in range(segs):
			var t0 := float(i) * 2.0 * dash_len / perimeter
			var t1 := (float(i) * 2.0 + 1.0) * dash_len / perimeter
			var p0 := _rect_perimeter_point(rect, t0)
			var p1 := _rect_perimeter_point(rect, t1)
			draw_line(p0, p1, Color(1, 1, 1, 0.7), 1.5)

func _rect_perimeter_point(rect: Rect2, t: float) -> Vector2:
	# t in [0,1] 沿矩形周长
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var per := 2.0 * (w + h)
	var d := t * per
	if d < w:
		return Vector2(x + d, y)
	d -= w
	if d < h:
		return Vector2(x + w, y + d)
	d -= h
	if d < w:
		return Vector2(x + w - d, y + h)
	d -= w
	return Vector2(x, y + h - d)

func _draw_zombies() -> void:
	var font := ThemeDB.fallback_font
	for z in sim.zombies:
		var col: Color = COLOR_ZOMBIE.get(z.kind, COLOR_ZOMBIE[Zombie.Kind.WALKER])
		var radius := TILE * 0.28
		var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
		var p: Vector2 = z.prev_pos.lerp(z.pos, alpha)
		var center := Vector2(p.x * TILE, p.y * TILE)
		# 身体
		draw_circle(center, radius, col.darkened(0.1))
		draw_circle(center, radius * 0.75, col)
		# 朝向核心的小眼睛
		var core := _grid_center_world()
		var to_core := (core - center).normalized()
		draw_circle(center + to_core * radius * 0.35, radius * 0.22, Color(0.1, 0.1, 0.1))
		draw_circle(center + to_core * radius * 0.42, radius * 0.08, Color(1, 1, 1, 0.9))
		# HP 条
		if z.hp < z.max_hp:
			_draw_hp_bar(center - Vector2(radius, radius + 10), radius * 2.0, z.hp, z.max_hp)
		# 种类符号（调试/可读）
		var sym := "走" if z.kind == Zombie.Kind.WALKER else ("跑" if z.kind == Zombie.Kind.RUNNER else "喷")
		var ts := font.get_string_size(sym, 10)
		draw_string(font, center - ts / 2.0, sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.9))

func _sync_state() -> void:
	update_hud()
	queue_redraw()

func update_hud() -> void:
	if hud:
		hud.set_state(sim.state, sim.wave, sim.zombies.size(), sim.scrap, sim.biomass, selected_type)
