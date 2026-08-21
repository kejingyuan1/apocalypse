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
const COLOR_GRID := Color(0.22, 0.22, 0.24)
const COLOR_GRID_STRONG := Color(0.30, 0.30, 0.33)
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

# —— 精灵表配置（AtlasTexture 切片）——
const ROOM_SHEETS := {
	RoomDefs.Type.WALL:       {"path": "res://assets/sheets/wall.png",       "anim": "wall",  "frames": 2, "fps": 1.0},
	RoomDefs.Type.DEFENSE:    {"path": "res://assets/sheets/turret_idle.png", "anim": "idle",  "frames": 1, "fps": 1.0},
	RoomDefs.Type.PRODUCTION: {"path": "res://assets/sheets/production.png",  "anim": "work",  "frames": 4, "fps": 5.0},
	RoomDefs.Type.COMMAND:    {"path": "res://assets/sheets/core.png",        "anim": "pulse", "frames": 4, "fps": 6.0},
}
const ZOMBIE_SHEETS := {
	Zombie.Kind.WALKER: "res://assets/sheets/zombie_walker.png",
	Zombie.Kind.RUNNER: "res://assets/sheets/zombie_runner.png",
	Zombie.Kind.SPITTER: "res://assets/sheets/zombie_spitter.png",
}

@onready var hud: HUD = $HUD

var grid: GridModel
var sim: BattleSim
var selected_kind: int = Zombie.Kind.WALKER
var tick_acc: float = 0.0
var camera: Camera2D
var anim_time: float = 0.0

var bg_layer: BGLayer
var unit_layer: Node2D
var fx_layer: FXLayer

# —— 动画状态 ——
var particles: Array = []
var bullets: Array = []
var turret_aim: Dictionary = {}
var turret_flash: Dictionary = {}
var room_flash: Dictionary = {}
var core_flash: float = 0.0
var prev_unit_ids: Dictionary = {}
var prev_room_hp: Dictionary = {}
var prev_core_hp: int = -1
var dust_acc: float = 0.0
var smoke_acc: Dictionary = {}

# —— 实体精灵实例 ——
var room_sprites: Dictionary = {}
var unit_sprites: Dictionary = {}
var _frames_cache: Dictionary = {}
var _shot_pending: bool = false
var _shot_frames: int = 0

func _ready() -> void:
	_setup_layers()
	grid = GridModel.new()
	# 战斗内核会自行设定网格尺寸并生成敌方基地
	sim = BattleSim.new(grid)
	_setup_camera()
	_sync_rooms()
	_sync_state()
	if OS.get_cmdline_args().has("--shot"):
		_dev_shot_setup()

func _setup_layers() -> void:
	bg_layer = BGLayer.new(); bg_layer.main = self; add_child(bg_layer)
	unit_layer = Node2D.new(); add_child(unit_layer)
	fx_layer = FXLayer.new(); fx_layer.main = self; add_child(fx_layer)

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
	var z: float = min(avail_w, avail_h) / world_px
	z = clampf(z, 0.25, 10.0)
	camera.zoom = Vector2(z, z)

func _grid_center_world() -> Vector2:
	return Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0)

# ===================== 输入 =====================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if sim.state == "deploy" or sim.state == "combat":
				deploy_at(world_to_cell(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: selected_kind = Zombie.Kind.WALKER
			KEY_2: selected_kind = Zombie.Kind.RUNNER
			KEY_3: selected_kind = Zombie.Kind.SPITTER
		_sync_state()

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / TILE), floor(p.y / TILE))

func deploy_at(c: Vector2i) -> void:
	var ok: bool = sim.deploy(selected_kind, c)
	if ok:
		var rc := Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
		_spawn_dust(rc, COLOR_UNIT[selected_kind], 0.8)
		_sync_state()

# ===================== 主循环 =====================
func _process(delta: float) -> void:
	anim_time += delta
	_update_particles(delta)
	_update_bullets(delta)
	_decay(room_flash, delta)
	_decay(turret_flash, delta)
	if core_flash > 0.0:
		core_flash = max(0.0, core_flash - delta)

	_update_turret_idle(delta)
	_sync_rooms()
	_sync_units()
	if sim.state == "combat":
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
			if room_sprites.has(tid):
				room_sprites[tid].play("fire")
	for ev: Vector2 in sim.hit_events:
		_spawn_spark(ev * TILE, COLOR_BULLET, 0.25)
		_spawn_spark(ev * TILE, COLOR_UNIT[Zombie.Kind.WALKER], 0.3)

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
			var cc := _room_center_world(grid.rooms[sim.core_id])
			_spawn_spark(cc, COLOR_HP_RED, 0.4)
		prev_core_hp = hp
	for rid: int in grid.rooms:
		var hp: int = grid.rooms[rid]["hp"]
		if prev_room_hp.has(rid) and hp < prev_room_hp[rid]:
			room_flash[rid] = 0.25
			var rc := _room_center_world(grid.rooms[rid])
			_spawn_spark(rc, COLOR_ROCK_HI, 0.25)
		prev_room_hp[rid] = hp

func _update_turret_idle(delta: float) -> void:
	for rid: int in grid.rooms:
		if grid.rooms[rid]["type"] != RoomDefs.Type.DEFENSE:
			continue
		var rc := _room_center_world(grid.rooms[rid])
		var target := _angle_to_core(rc)
		if not turret_aim.has(rid):
			turret_aim[rid] = target
		else:
			turret_aim[rid] = _lerp_angle(turret_aim[rid], target + sin(anim_time + rid) * 0.4, 0.05)

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

func _make_turret_frames() -> SpriteFrames:
	var key := "TURRET"
	if _frames_cache.has(key):
		return _frames_cache[key]
	var idle_tex := load("res://assets/sheets/turret_idle.png") as Texture2D
	var fire_tex := load("res://assets/sheets/turret_fire.png") as Texture2D
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 1.0)
	sf.set_animation_loop("idle", true)
	var at0 := AtlasTexture.new(); at0.atlas = idle_tex; at0.region = Rect2(0, 0, idle_tex.get_width(), idle_tex.get_height()); sf.add_frame("idle", at0)
	sf.add_animation("fire")
	sf.set_animation_speed("fire", 12.0)
	sf.set_animation_loop("fire", false)
	for i: int in range(4):
		var at := AtlasTexture.new()
		at.atlas = fire_tex
		at.region = Rect2(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE)
		sf.add_frame("fire", at)
	_frames_cache[key] = sf
	return sf

func _sync_rooms() -> void:
	for id: int in grid.rooms:
		if room_sprites.has(id):
			continue
		var r: Dictionary = grid.rooms[id]
		var type: int = r["type"]
		var sp := AnimatedSprite2D.new()
		match type:
			RoomDefs.Type.DEFENSE:
				sp.sprite_frames = _make_turret_frames()
				sp.play("idle")
				sp.animation_finished.connect(func(): _on_turret_finished(id))
			RoomDefs.Type.WALL:
				var cfg = ROOM_SHEETS[RoomDefs.Type.WALL]
				sp.sprite_frames = _make_frames(cfg.path, cfg.anim, cfg.frames, cfg.fps, false)
				sp.play("wall")
			_:
				var cfg = ROOM_SHEETS[type]
				sp.sprite_frames = _make_frames(cfg.path, cfg.anim, cfg.frames, cfg.fps, true)
				sp.play(cfg.anim)
		sp.position = _room_center_world(r)
		unit_layer.add_child(sp)
		room_sprites[id] = sp

	for id: int in room_sprites:
		if not grid.rooms.has(id):
			continue
		var sp: AnimatedSprite2D = room_sprites[id]
		var r: Dictionary = grid.rooms[id]
		sp.position = _room_center_world(r)
		match r["type"]:
			RoomDefs.Type.DEFENSE:
				sp.rotation = float(turret_aim.get(id, 0.0)) + PI / 2.0
			RoomDefs.Type.WALL:
				var ratio := float(r["hp"]) / float(RoomDefs.hp(RoomDefs.Type.WALL))
				sp.frame = 0 if ratio > 0.5 else 1
	for id: int in room_sprites.keys():
		if not grid.rooms.has(id):
			room_sprites[id].queue_free()
			room_sprites.erase(id)

func _on_turret_finished(id: int) -> void:
	if room_sprites.has(id) and room_sprites[id].animation == "fire":
		room_sprites[id].play("idle")

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
		hud.set_state(sim.state, sim.army, sim.units.size(), sim.army_total, selected_kind)

# ===================== 开发期截图 =====================
func _dev_shot_setup() -> void:
	# 敌方基地由 sim 自动生成；这里在四周空地批量下满部队，并推进若干 tick 制造战斗画面
	var s: int = grid.size
	var cells: Array = []
	for y in [1, 2, s - 2, s - 3]:
		for x in range(1, s - 1):
			cells.append(Vector2i(x, y))
	var order := [Zombie.Kind.WALKER, Zombie.Kind.RUNNER, Zombie.Kind.SPITTER]
	var ci := 0
	for k in order:
		while sim.army[k] > 0 and ci < cells.size():
			if sim.deploy(k, cells[ci]):
				ci += 1
	for i in range(10):
		sim.tick()
		_consume_sim_events()
		_detect_state_changes()
	_sync_state()
	RenderingServer.viewport_set_update_mode(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_shot_pending = true

# ===================== 内部分层节点 =====================
class BGLayer extends Node2D:
	var main: Node

	func _draw() -> void:
		_draw_mountain()

	func _draw_mountain() -> void:
		var grid: GridModel = main.grid
		var W := grid.size * TILE
		var R: float = W * 2.0
		draw_rect(Rect2(Vector2(-R, -R), Vector2(R * 2.0, R * 2.0)), COLOR_SKY)
		# 山体边框（凿穿山体建成要塞）
		var border := TILE * 1.7
		draw_rect(Rect2(Vector2(-border, -border), Vector2(W + border * 2.0, border)), COLOR_ROCK)
		draw_rect(Rect2(Vector2(-border, W), Vector2(W + border * 2.0, border)), COLOR_ROCK)
		draw_rect(Rect2(Vector2(-border, -border), Vector2(border, W + border * 2.0)), COLOR_ROCK)
		draw_rect(Rect2(Vector2(W, -border), Vector2(border, W + border * 2.0)), COLOR_ROCK)
		for i in range(40):
			var rx := -border + _hash(i * 1.7) * (W + border * 2.0)
			var ry := -border + _hash(i * 3.1 + 5.0) * (W + border * 2.0)
			var sz := 4.0 + _hash(i * 5.3) * 10.0
			draw_rect(Rect2(Vector2(rx, ry), Vector2(sz, sz)), COLOR_ROCK_LO if i % 2 == 0 else COLOR_ROCK_HI)
		for i in range(int(W / (TILE * 1.5)) + 1):
			var x := i * TILE * 1.5 + _hash(i * 2.2) * 10.0
			var h := 10.0 + _hash(i * 4.4) * 16.0
			_fill_poly(_tri(Vector2(x, -border), Vector2(x + 12, -border), Vector2(x + 6, -border + h)), COLOR_ROCK_LO)
		# 棋盘地面
		for x in range(grid.size):
			for y in range(grid.size):
				var col := COLOR_FLOOR_A if (x + y) % 2 == 0 else COLOR_FLOOR_B
				draw_rect(Rect2(Vector2(x * TILE, y * TILE), Vector2(TILE, TILE)), col)
		# 核心光晕
		var cc := Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0)
		for r in range(6, 0, -1):
			var a := 0.05 * (r / 6.0)
			draw_circle(cc, float(r) * TILE * 0.5, Color(0.91, 0.57, 0.24, a))
		# 网格线
		for i in range(grid.size + 1):
			var col := COLOR_GRID_STRONG if i % 3 == 0 else COLOR_GRID
			draw_line(Vector2(i * TILE, 0), Vector2(i * TILE, W), col, 1.5 if i % 3 == 0 else 1.0)
			draw_line(Vector2(0, i * TILE), Vector2(W, i * TILE), col, 1.5 if i % 3 == 0 else 1.0)

	func _fill_poly(pts: PackedVector2Array, col: Color) -> void:
		draw_polygon(pts, PackedColorArray([col]))

	func _tri(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
		return PackedVector2Array([a, b, c])

	func _hash(n: float) -> float:
		var s := sin(n * 12.9898) * 43758.5453
		return s - floor(s)


class FXLayer extends Node2D:
	var main: Node

	func _draw() -> void:
		_draw_hp_bars()
		_draw_flashes()
		_draw_deploy_preview()
		_draw_bullets()
		_draw_particles()

	func _draw_hp_bars() -> void:
		var grid: GridModel = main.grid
		var sim: BattleSim = main.sim
		var tick_acc: float = main.tick_acc
		for id: int in grid.rooms:
			var r: Dictionary = grid.rooms[id]
			if r["hp"] < RoomDefs.hp(r["type"]):
				var origin := Vector2(r["origin"].x * TILE + 2.0, r["origin"].y * TILE - 9.0)
				_draw_hp_bar(origin, RoomDefs.size(r["type"]).x * TILE - 4.0, r["hp"], RoomDefs.hp(r["type"]))
		var zr := TILE * 0.26
		for z: Zombie in sim.units:
			if z.hp < z.max_hp:
				var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
				var p: Vector2 = z.prev_pos.lerp(z.pos, alpha)
				var wp: Vector2 = p * TILE
				_draw_hp_bar(wp - Vector2(zr, zr + 12), zr * 2.0, z.hp, z.max_hp)

	func _draw_hp_bar(origin: Vector2, width: float, hp: int, max_hp: int) -> void:
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_h := 5.0
		draw_rect(Rect2(origin, Vector2(width, bar_h)), COLOR_HP_BG)
		var col := COLOR_HP_GREEN if ratio > 0.6 else (COLOR_HP_ORANGE if ratio > 0.3 else COLOR_HP_RED)
		draw_rect(Rect2(origin, Vector2(width * ratio, bar_h)), col)

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
		var grid: GridModel = main.grid
		var sim: BattleSim = main.sim
		if sim.state != "deploy" and sim.state != "combat":
			return
		var c: Vector2i = main.world_to_cell(get_global_mouse_position())
		if c.x < 0 or c.y < 0 or c.x >= grid.size or c.y >= grid.size:
			return
		var ok: bool = (not grid.occupied.has(c))
		var col: Color = main.COLOR_DEPLOY_OK if ok else main.COLOR_DEPLOY_BAD
		var rect := Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(TILE, TILE))
		draw_rect(rect, col)
		var cx := c.x * TILE + TILE / 2.0
		var cy := c.y * TILE + TILE / 2.0
		draw_circle(Vector2(cx, cy), TILE * 0.28, main.COLOR_UNIT[main.selected_kind])
		draw_arc(Vector2(cx, cy), TILE * 0.28, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 2.0)

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
				_:
					draw_circle(p["pos"], p["size"] * clamp(life, 0.2, 1.0), col)
