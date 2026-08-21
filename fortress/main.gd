extends Node2D

# Phase 4 垂直切片：建造 + 波次最小闭环（build → defend → expand）
# 渲染/输入翻译层：逻辑全部在 core/（服务端可移植），本脚本只做输入翻译与快照插值渲染。

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Zombie := preload("res://core/zombie.gd")
const HUD := preload("res://hud.gd")

const TILE := 32

@onready var hud: HUD = $HUD

var grid: GridModel
var sim: BattleSim
var zombie_sprites: Dictionary = {}   # zombie.id -> Sprite2D
var room_sprites: Dictionary = {}     # room_id -> Sprite2D
var tick_acc: float = 0.0
var selected_type: int = RoomDefs.Type.DEFENSE

func _ready() -> void:
	grid = GridModel.new()
	grid.set_level(1)
	var center = Vector2i(grid.size / 2 - 2, grid.size / 2 - 2)
	var cid = grid.place(RoomDefs.Type.COMMAND, center)
	if cid >= 0:
		_spawn_room_sprite(cid)
	sim = BattleSim.new(grid)
	_sync_state()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if sim.state == "build":
				try_place(world_to_cell(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if sim.state == "build":
				_demolish_at_cell(world_to_cell(event.position))
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: selected_type = RoomDefs.Type.WALL
			KEY_2: selected_type = RoomDefs.Type.DEFENSE
			KEY_3: selected_type = RoomDefs.Type.PRODUCTION
			KEY_X, KEY_DELETE: _demolish_at_mouse()
			KEY_U: _upgrade_at_mouse()
			KEY_SPACE: start_wave()
		_sync_state()

# 取鼠标当前悬停格上所属房间 id（建造态操作目标）
func _pick_room_id() -> int:
	var c: Vector2i = world_to_cell(get_global_mouse_position())
	return grid.occupied.get(c, -1)

func _demolish_at_cell(c: Vector2i) -> void:
	var id: int = grid.occupied.get(c, -1)
	if id < 0:
		return
	var refund: int = sim.try_demolish(id)
	if refund >= 0:
		var sp: Sprite2D = room_sprites.get(id)
		if sp:
			sp.queue_free()
			room_sprites.erase(id)
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
		_spawn_room_sprite(id)
		_sync_state()

func _spawn_room_sprite(id: int) -> void:
	var r: Dictionary = grid.rooms[id]
	var sp := Sprite2D.new()
	sp.texture = RoomDefs.texture(r["type"])
	var s: Vector2i = RoomDefs.size(r["type"])
	sp.position = Vector2(r["origin"].x * TILE, r["origin"].y * TILE) + Vector2(s.x * TILE / 2, s.y * TILE / 2)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素风硬边
	add_child(sp)
	room_sprites[id] = sp

func start_wave() -> void:
	if sim.state != "build":
		return
	sim.begin_wave(sim.wave + 1)
	# 为每只丧尸创建精灵（与 sim 快照 id 对齐）
	for z in sim.zombies:
		if not zombie_sprites.has(z.id):
			var sp := Sprite2D.new()
			sp.texture = Zombie.texture(z.kind)
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(sp)
			zombie_sprites[z.id] = sp
	tick_acc = 0.0
	_sync_state()

func _process(delta: float) -> void:
	if sim.state != "combat":
		return
	tick_acc += delta
	if tick_acc >= BattleSim.TICK:
		tick_acc -= BattleSim.TICK
		sim.tick()
		_reconcile_sprites()
		_sync_state()
		if sim.state != "combat":
			return
	# 快照插值：prev_pos → pos，平滑渲染（play 1Hz tick）
	var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
	for z in sim.zombies:
		var sp: Sprite2D = zombie_sprites.get(z.id)
		if sp:
			var p: Vector2 = z.prev_pos.lerp(z.pos, alpha)
			sp.position = Vector2(p.x * TILE, p.y * TILE)

# 同步：清除阵亡丧尸精灵
func _reconcile_sprites() -> void:
	var alive := {}
	for z in sim.zombies:
		alive[z.id] = true
	for id in zombie_sprites.keys():
		if not alive.has(id):
			zombie_sprites[id].queue_free()
			zombie_sprites.erase(id)

func _sync_state() -> void:
	update_hud()

func update_hud() -> void:
	if hud:
		hud.set_state(sim.state, sim.wave, sim.zombies.size(), sim.scrap, sim.biomass, selected_type)
