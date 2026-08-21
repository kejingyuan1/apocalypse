extends Node2D
class_name Game

# Phase 4 垂直切片：建造 + 波次最小闭环
# 逻辑放 core/（可服务端化），本脚本只做输入翻译与渲染

const TILE := 32

@onready var hud = $HUD

var grid: GridModel
var zombies = []          # Array[Zombie]
var zombie_sprites = []    # Array[Sprite2D] 与 zombies 平行
var room_sprites = {}      # room_id -> Sprite2D
var wave: int = 0
var state: String = "build"   # build | combat | win
var scrap: int = 200
var tick_acc: float = 0.0
var selected_type: int = RoomDefs.Type.DEFENSE

func _ready() -> void:
	grid = GridModel.new()
	grid.set_level(1)
	# 初始指挥房置于网格中心
	var center = Vector2i(grid.size / 2 - 2, grid.size / 2 - 2)
	var cid = grid.place(RoomDefs.Type.COMMAND, center)
	if cid >= 0:
		_spawn_room_sprite(cid)
	update_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c = world_to_cell(event.position)
		if state == "build":
			try_place(c)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: selected_type = RoomDefs.Type.WALL
			KEY_2: selected_type = RoomDefs.Type.DEFENSE
			KEY_3: selected_type = RoomDefs.Type.PRODUCTION
			KEY_SPACE: start_wave()
		update_hud()

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / TILE), floor(p.y / TILE))

func try_place(c: Vector2i) -> void:
	if not grid.can_place(selected_type, c):
		return
	var cost = 20 if selected_type != RoomDefs.Type.COMMAND else 0
	if scrap < cost:
		return
	scrap -= cost
	var id = grid.place(selected_type, c)
	if id >= 0:
		_spawn_room_sprite(id)
	update_hud()

func _spawn_room_sprite(id: int) -> void:
	var r = grid.rooms[id]
	var sp = Sprite2D.new()
	sp.texture = RoomDefs.texture(r["type"])
	var s = RoomDefs.size(r["type"])
	sp.position = Vector2(r["origin"].x * TILE, r["origin"].y * TILE) + Vector2(s.x * TILE / 2, s.y * TILE / 2)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素风硬边
	add_child(sp)
	room_sprites[id] = sp

func start_wave() -> void:
	if state != "build":
		return
	state = "combat"
	wave += 1
	var n = WaveManager.count(wave)
	for i in range(n):
		var k = Zombie.Kind.WALKER
		if i % 5 == 0:
			k = Zombie.Kind.RUNNER
		elif i % 7 == 0:
			k = Zombie.Kind.SPITTER
		var z = Zombie.make(k)
		z.pos = Vector2(-20.0, randf_range(0.0, grid.size * TILE))
		zombies.append(z)
		var sp = Sprite2D.new()
		sp.texture = Zombie.texture(k)
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sp)
		zombie_sprites.append(sp)
	update_hud()

func _process(delta: float) -> void:
	if state != "combat":
		return
	tick_acc += delta
	if tick_acc >= WaveManager.tick_seconds():
		tick_acc -= WaveManager.tick_seconds()
		_tick()
	# 实时移动（演示：向中心指挥房推进）
	var target = Vector2(grid.size * TILE / 2, grid.size * TILE / 2)
	for i in range(zombies.size()):
		var z = zombies[i]
		var dir = target - z.pos
		if dir.length() > 1.0:
			z.pos += dir.normalized() * z.speed * delta
		zombie_sprites[i].position = z.pos
	# 本波清空
	if zombies.is_empty():
		for sp in zombie_sprites:
			sp.queue_free()
		zombie_sprites.clear()
		if wave >= 10:
			state = "win"
		else:
			state = "build"
		update_hud()

func _tick() -> void:
	# 固定 tick 逻辑占位：正式版在此结算破墙/防御开火/资源消耗
	pass

func update_hud() -> void:
	if hud:
		hud.set_state(state, wave, zombies.size(), scrap, selected_type)
