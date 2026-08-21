extends Node2D

# 《末日堡垒》渲染/输入翻译层（Phase 4 垂直切片）
# 逻辑全部在 core/（服务端可移植），本脚本只做输入翻译 + 矢量风格动画渲染。
# 主题：凿穿山体建成的地下堡垒（18×18 凿空空间 + 四向山洞出入口）。

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Zombie := preload("res://core/zombie.gd")
const HUD := preload("res://hud.gd")

const TILE := 40               # 单元格像素
const HUD_TOP := 44.0
const HUD_BOTTOM := 92.0

# —— 配色（末日地下堡垒：冷岩 + 暖橙威胁色，美术圣经单层暖橙铁律）——
const COLOR_SKY := Color(0.04, 0.05, 0.07)         # 洞外深渊
const COLOR_ROCK := Color(0.13, 0.12, 0.13)        # 山体岩石
const COLOR_ROCK_HI := Color(0.20, 0.19, 0.20)     # 岩面高光
const COLOR_ROCK_LO := Color(0.07, 0.07, 0.08)     # 岩缝阴影
const COLOR_FLOOR_A := Color(0.12, 0.12, 0.13)
const COLOR_FLOOR_B := Color(0.10, 0.10, 0.11)
const COLOR_GRID := Color(0.22, 0.22, 0.24)
const COLOR_GRID_STRONG := Color(0.30, 0.30, 0.33)
const COLOR_GATE := Color(0.02, 0.02, 0.03)
const COLOR_GATE_RIM := Color(0.45, 0.30, 0.18)
const COLOR_HOVER_OK := Color(0.30, 0.75, 0.40, 0.35)
const COLOR_HOVER_BAD := Color(0.90, 0.25, 0.25, 0.40)
const COLOR_HP_BG := Color(0.10, 0.10, 0.10)
const COLOR_HP_GREEN := Color(0.35, 0.82, 0.40)
const COLOR_HP_ORANGE := Color(0.91, 0.57, 0.24)
const COLOR_HP_RED := Color(0.88, 0.28, 0.28)
const COLOR_ZOMBIE := {
	Zombie.Kind.WALKER: Color(0.82, 0.52, 0.30),
	Zombie.Kind.RUNNER: Color(0.85, 0.30, 0.30),
	Zombie.Kind.SPITTER: Color(0.72, 0.34, 0.78),
}
const COLOR_BULLET := Color(1.0, 0.92, 0.55)

@onready var hud: HUD = $HUD

var grid: GridModel
var sim: BattleSim
var selected_type: int = RoomDefs.Type.DEFENSE
var tick_acc: float = 0.0
var camera: Camera2D
var anim_time: float = 0.0

# —— 动画状态 ——
var particles: Array = []                  # {pos,vel,life,max,col,size,kind}
var bullets: Array = []                   # {from,to,t,speed}
var turret_aim: Dictionary = {}           # room_id -> 当前炮口角度
var turret_flash: Dictionary = {}         # room_id -> 炮口闪光计时
var room_flash: Dictionary = {}           # room_id -> 受击闪白计时
var core_flash: float = 0.0
var prev_zombie_ids: Dictionary = {}      # id -> last pos
var prev_room_hp: Dictionary = {}          # id -> last hp
var prev_core_hp: int = -1
var dust_acc: float = 0.0
var smoke_acc: Dictionary = {}             # room_id -> 冒烟计时

func _ready() -> void:
	grid = GridModel.new()
	grid.set_level(1)
	var c := grid.size / 2 - 1
	var cid := grid.place(RoomDefs.Type.COMMAND, Vector2i(c, c))
	if cid >= 0:
		grid.rooms[cid]["hp"] = RoomDefs.hp(RoomDefs.Type.COMMAND)
		prev_room_hp[cid] = grid.rooms[cid]["hp"]
		prev_core_hp = grid.rooms[cid]["hp"]
	sim = BattleSim.new(grid)
	_setup_camera()
	_sync_state()
	# 开发期截图：传入 --shot 自动布防+开波+3.5s 后截图退出（正常游玩不会触发）
	if OS.get_cmdline_args().has("--shot"):
		_dev_shot_setup()

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
	return grid.occupied.get(world_to_cell(get_global_mouse_position()), -1)

func _demolish_at_cell(c: Vector2i) -> void:
	var id: int = grid.occupied.get(c, -1)
	if id < 0:
		return
	var refund: int = sim.try_demolish(id)
	if refund >= 0:
		turret_aim.erase(id)
		turret_flash.erase(id)
		room_flash.erase(id)
		prev_room_hp.erase(id)
		_sync_state()

func _demolish_at_mouse() -> void:
	_demolish_at_cell(world_to_cell(get_global_mouse_position()))

func _upgrade_at_mouse() -> void:
	var id: int = _pick_room_id()
	if id < 0:
		return
	var new_hp: int = sim.try_upgrade(id)
	if new_hp >= 0:
		room_flash[id] = 0.3
		_sync_state()

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floor(p.x / TILE), floor(p.y / TILE))

func try_place(c: Vector2i) -> void:
	var id: int = sim.try_place(selected_type, c)
	if id >= 0:
		grid.rooms[id]["hp"] = RoomDefs.hp(selected_type)
		prev_room_hp[id] = grid.rooms[id]["hp"]
		var rc := _room_center_world(grid.rooms[id])
		_spawn_ring(rc, RoomDefs.color(selected_type))   # 放置弹跳
		room_flash[id] = 0.2
		_sync_state()

func start_wave() -> void:
	if sim.state != "build":
		return
	sim.begin_wave(sim.wave + 1)
	tick_acc = 0.0
	# 出入口尘土（尸潮涌入）
	for e in sim.entrances:
		_spawn_dust(e * TILE, COLOR_ROCK_HI, 0.9)
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

	if sim.state == "combat":
		tick_acc += delta
		if tick_acc >= BattleSim.TICK:
			tick_acc -= BattleSim.TICK
			sim.tick()
			_consume_sim_events()
			_detect_state_changes()
			_sync_state()
	else:
		# 建造态：核心缓慢呼吸、塔待机扫描
		_update_turret_idle(delta)

	_update_ambient(delta)
	queue_redraw()

func _decay(d: Dictionary, delta: float) -> void:
	for k in d.keys():
		d[k] = max(0.0, float(d[k]) - delta)
		if d[k] <= 0.0:
			d.erase(k)

# 消费本 tick 的开火/命中事件 → 子弹 + 炮口闪光 + 命中火花
func _consume_sim_events() -> void:
	for ev: Dictionary in sim.fire_events:
		var f: Vector2 = ev["from"] * TILE
		var t: Vector2 = ev["to"] * TILE
		bullets.append({"from": f, "to": t, "t": 0.0, "speed": 1400.0})
		# 找塔 id（最近防御房）
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
	for ev: Vector2 in sim.hit_events:
		_spawn_spark(ev * TILE, COLOR_BULLET, 0.25)
		_spawn_spark(ev * TILE, COLOR_ZOMBIE[Zombie.Kind.WALKER], 0.3)

# 检测：新丧尸 / 死亡 / 核心受损 / 房间受损 → 粒子 + 闪白
func _detect_state_changes() -> void:
	var cur: Dictionary = {}
	for z: Zombie in sim.zombies:
		cur[z.id] = z.pos
		if not prev_zombie_ids.has(z.id):
			_spawn_dust(z.pos * TILE, COLOR_ROCK_HI, 1.0)   # 钻出山洞的尘土
		prev_zombie_ids[z.id] = z.pos
	# 死亡
	for id: int in prev_zombie_ids.keys():
		if not cur.has(id):
			var p: Vector2 = prev_zombie_ids[id] * TILE
			_spawn_spark(p, Color(0.5, 0.35, 0.25), 0.4)
			_spawn_dust(p, Color(0.35, 0.25, 0.2), 0.5)
			prev_zombie_ids.erase(id)
	# 核心受损
	if sim.core_id >= 0 and grid.rooms.has(sim.core_id):
		var hp: int = grid.rooms[sim.core_id]["hp"]
		if prev_core_hp >= 0 and hp < prev_core_hp:
			core_flash = 0.3
			var cc := _room_center_world(grid.rooms[sim.core_id])
			_spawn_spark(cc, COLOR_HP_RED, 0.4)
		prev_core_hp = hp
	# 房间受损
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

# ===================== 绘制 =====================
func _draw() -> void:
	_draw_mountain()
	_draw_rooms()
	_draw_hover_preview()
	_draw_bullets()
	_draw_zombies()
	_draw_particles()

func _draw_mountain() -> void:
	var W := grid.size * TILE
	# 洞外深渊背景（全屏覆盖）
	var R: float = W * 2.0
	draw_rect(Rect2(Vector2(-R, -R), Vector2(R * 2.0, R * 2.0)), COLOR_SKY)
	# 山体岩石外框
	var border := TILE * 1.7
	draw_rect(Rect2(Vector2(-border, -border), Vector2(W + border * 2.0, border)), COLOR_ROCK)
	draw_rect(Rect2(Vector2(-border, W), Vector2(W + border * 2.0, border)), COLOR_ROCK)
	draw_rect(Rect2(Vector2(-border, -border), Vector2(border, W + border * 2.0)), COLOR_ROCK)
	draw_rect(Rect2(Vector2(W, -border), Vector2(border, W + border * 2.0)), COLOR_ROCK)
	# 岩面纹理（确定性噪声，避免每帧抖动）
	for i in range(40):
		var rx := -border + _hash(i * 1.7) * (W + border * 2.0)
		var ry := -border + _hash(i * 3.1 + 5.0) * (W + border * 2.0)
		var s := 4.0 + _hash(i * 5.3) * 10.0
		draw_rect(Rect2(Vector2(rx, ry), Vector2(s, s)), COLOR_ROCK_LO if i % 2 == 0 else COLOR_ROCK_HI)
	# 顶部钟乳石（指向洞内）
	for i in range(int(W / (TILE * 1.5)) + 1):
		var x := i * TILE * 1.5 + _hash(i * 2.2) * 10.0
		var h := 10.0 + _hash(i * 4.4) * 16.0
		_fill_poly(_tri(Vector2(x, -border), Vector2(x + 12, -border), Vector2(x + 6, -border + h)), COLOR_ROCK_LO)
	# 凿空地面
	for x in range(grid.size):
		for y in range(grid.size):
			var col := COLOR_FLOOR_A if (x + y) % 2 == 0 else COLOR_FLOOR_B
			draw_rect(Rect2(Vector2(x * TILE, y * TILE), Vector2(TILE, TILE)), col)
	# 核心暖光（灯笼照明感）
	var cc := _grid_center_world()
	for r in range(6, 0, -1):
		var a := 0.05 * (r / 6.0)
		draw_circle(cc, float(r) * TILE * 0.5, Color(0.91, 0.57, 0.24, a))
	# 网格线（细）
	for i in range(grid.size + 1):
		var col := COLOR_GRID_STRONG if i % 3 == 0 else COLOR_GRID
		draw_line(Vector2(i * TILE, 0), Vector2(i * TILE, W), col, 1.5 if i % 3 == 0 else 1.0)
		draw_line(Vector2(0, i * TILE), Vector2(W, i * TILE), col, 1.5 if i % 3 == 0 else 1.0)
	# 山洞出入口（隧道口）
	for e: Vector2 in sim.entrances:
		_draw_gate(e * TILE)

func _draw_gate(g: Vector2) -> void:
	var w := TILE * 1.1
	var h := TILE * 1.3
	# 洞口（朝向网格内侧）
	var inward := Vector2(grid.size * TILE / 2.0, grid.size * TILE / 2.0) - g
	if abs(inward.x) > abs(inward.y):
		h = TILE * 1.1; w = TILE * 1.3
	draw_circle(g, w * 0.6, COLOR_GATE)
	draw_arc(g, w * 0.6, 0.0, TAU, 24, COLOR_GATE_RIM, 4.0)
	# 门楣标记
	var font := ThemeDB.fallback_font
	draw_string(font, g - Vector2(8, w * 0.6 + 4), "洞", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, COLOR_GATE_RIM)

func _draw_rooms() -> void:
	for id: int in grid.rooms:
		var r: Dictionary = grid.rooms[id]
		var type: int = r["type"]
		var origin: Vector2i = r["origin"]
		var sz: Vector2i = RoomDefs.size(type)
		var px := Vector2(origin.x * TILE, origin.y * TILE)
		var pw := Vector2(sz.x * TILE, sz.y * TILE)
		var rect := Rect2(px, pw)
		match type:
			RoomDefs.Type.WALL: _draw_wall(rect, r)
			RoomDefs.Type.DEFENSE: _draw_turret(rect, r, id)
			RoomDefs.Type.PRODUCTION: _draw_production(rect, r, id)
			RoomDefs.Type.COMMAND: _draw_core(rect, r)
		# HP 条
		if r["hp"] < RoomDefs.hp(type):
			_draw_hp_bar(Vector2(px.x + 2, px.y - 9), pw.x - 4, r["hp"], RoomDefs.hp(type))
		# 受击闪白
		if room_flash.has(id):
			draw_rect(rect, Color(1, 1, 1, 0.5 * (room_flash[id] / 0.3)))

func _draw_wall(rect: Rect2, r: Dictionary) -> void:
	var base := RoomDefs.color(RoomDefs.Type.WALL)
	draw_rect(rect, base.darkened(0.1))
	draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), base)
	# 砖缝
	var brick := base.darkened(0.3)
	for i in range(1, 3):
		var yy := rect.position.y + rect.size.y * i / 3.0
		draw_line(Vector2(rect.position.x + 2, yy), Vector2(rect.position.x + rect.size.x - 2, yy), brick, 1.0)
	draw_line(Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y + 2), Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0), brick, 1.0)
	# 受损裂纹
	var ratio := float(r["hp"]) / float(RoomDefs.hp(RoomDefs.Type.WALL))
	if ratio < 0.6:
		var crack := base.darkened(0.5)
		draw_line(rect.position + rect.size * 0.3, rect.position + rect.size * 0.7, crack, 2.0)
		if ratio < 0.3:
			draw_line(rect.position + rect.size * 0.5, rect.position + rect.size * 0.2, crack, 2.0)

func _draw_turret(rect: Rect2, r: Dictionary, id: int) -> void:
	var center := rect.position + rect.size / 2.0
	var base := RoomDefs.color(RoomDefs.Type.DEFENSE)
	# 底座
	draw_circle(center, rect.size.x * 0.42, base.darkened(0.25))
	draw_circle(center, rect.size.x * 0.34, base)
	# 炮管（朝瞄准角）
	var ang := float(turret_aim.get(id, 0.0))
	_rot_rect(center + Vector2(cos(ang), sin(ang)) * rect.size.x * 0.18, rect.size.x * 0.5, 7.0, ang, base.lightened(0.15))
	draw_circle(center + Vector2(cos(ang), sin(ang)) * rect.size.x * 0.42, 4.0, base.lightened(0.3))
	# 炮口闪光
	if turret_flash.has(id):
		var fa: float = turret_flash[id] / 0.12
		draw_circle(center + Vector2(cos(ang), sin(ang)) * rect.size.x * 0.45, 6.0 * fa + 2.0, COLOR_BULLET)
	# 旋转指示灯
	var spin := anim_time * 2.0 + id
	draw_circle(center + Vector2(cos(spin), sin(spin)) * rect.size.x * 0.18, 2.5, Color(0.6, 0.9, 1.0, 0.8))

func _draw_production(rect: Rect2, r: Dictionary, id: int) -> void:
	var base := RoomDefs.color(RoomDefs.Type.PRODUCTION)
	draw_rect(rect, base.darkened(0.15))
	draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), base)
	# 烟囱
	var chim := rect.position + Vector2(rect.size.x * 0.7, 2.0)
	draw_rect(Rect2(chim, Vector2(6, rect.size.y * 0.4)), base.darkened(0.3))
	# 齿轮/能量符号
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + rect.size / 2.0 - Vector2(8, 8), "产", HORIZONTAL_ALIGNMENT_CENTER, -1, int(rect.size.y * 0.5), Color(1, 1, 1, 0.9))

func _draw_core(rect: Rect2, r: Dictionary) -> void:
	var center := rect.position + rect.size / 2.0
	var base := RoomDefs.color(RoomDefs.Type.COMMAND)
	var pulse := 0.5 + 0.5 * sin(anim_time * 2.5)
	# 外发光
	draw_circle(center, rect.size.x * 0.62 + pulse * 4.0, Color(0.91, 0.57, 0.24, 0.12 + pulse * 0.10))
	# 主体
	draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), base.darkened(0.1))
	draw_rect(Rect2(rect.position + rect.size * 0.2, rect.size * 0.6), base.lightened(0.1))
	# 内部旋转核心
	var spin := anim_time * 1.5
	var inner := PackedVector2Array()
	for i in 6:
		var a := spin + float(i) / 6.0 * TAU
		inner.append(center + Vector2(cos(a), sin(a)) * rect.size.x * 0.18)
	_fill_poly(inner, base.lightened(0.35))
	draw_circle(center, rect.size.x * 0.1, Color(1, 0.9, 0.7, 0.9))
	# 符号
	var font := ThemeDB.fallback_font
	draw_string(font, center - Vector2(10, 10), "核", HORIZONTAL_ALIGNMENT_CENTER, -1, int(rect.size.x * 0.42), Color(1, 1, 1, 0.95))
	# 受损闪红
	if core_flash > 0.0:
		draw_rect(Rect2(rect.position, rect.size), Color(1, 0.3, 0.3, 0.5 * (core_flash / 0.3)))
	# HP 环
	var ratio := clampf(float(r["hp"]) / float(RoomDefs.hp(RoomDefs.Type.COMMAND)), 0.0, 1.0)
	draw_arc(center, rect.size.x * 0.62, -PI / 2.0, -PI / 2.0 + TAU * ratio, 40,
		COLOR_HP_GREEN if ratio > 0.6 else (COLOR_HP_ORANGE if ratio > 0.3 else COLOR_HP_RED), 3.0)

func _draw_hover_preview() -> void:
	if sim.state != "build":
		return
	var c: Vector2i = world_to_cell(get_global_mouse_position())
	if c.x < 0 or c.y < 0 or c.x >= grid.size or c.y >= grid.size:
		return
	var hover_id: int = grid.occupied.get(c, -1)
	if hover_id >= 0 and grid.rooms[hover_id]["type"] == RoomDefs.Type.DEFENSE:
		var center := Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
		var radius := BattleSim.DEFENSE_RANGE_CELLS * TILE
		draw_circle(center, radius, Color(0.20, 0.58, 0.82, 0.08))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.20, 0.58, 0.82, 0.35), 1.5)
	if selected_type == RoomDefs.Type.DEFENSE:
		var center := Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
		var radius := BattleSim.DEFENSE_RANGE_CELLS * TILE
		draw_circle(center, radius, Color(0.20, 0.58, 0.82, 0.10))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.20, 0.58, 0.82, 0.40), 1.5)
	var sz: Vector2i = RoomDefs.size(selected_type)
	var rect := Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(sz.x * TILE, sz.y * TILE))
	var cost: int = BattleSim.ROOM_COST.get(selected_type, 20)
	var ok := (sim.scrap >= cost) and grid.can_place(selected_type, c)
	draw_rect(rect, COLOR_HOVER_OK if ok else COLOR_HOVER_BAD)
	var dash_len := 6.0
	var perimeter := 2.0 * (rect.size.x + rect.size.y)
	if perimeter > 0:
		var segs := int(perimeter / (dash_len * 2.0))
		for i in range(segs):
			var t0 := float(i) * 2.0 * dash_len / perimeter
			var t1 := (float(i) * 2.0 + 1.0) * dash_len / perimeter
			draw_line(_rect_perimeter_point(rect, t0), _rect_perimeter_point(rect, t1), Color(1, 1, 1, 0.7), 1.5)

func _draw_zombies() -> void:
	for z: Zombie in sim.zombies:
		var col: Color = COLOR_ZOMBIE.get(z.kind, COLOR_ZOMBIE[Zombie.Kind.WALKER])
		var alpha: float = clamp(tick_acc / BattleSim.TICK, 0.0, 1.0)
		var p: Vector2 = z.prev_pos.lerp(z.pos, alpha)
		var wp := p * TILE
		# 朝向
		var dir := z.pos - z.prev_pos
		if dir.length() < 0.001:
			dir = _grid_center_world() - wp
		var facing := dir.normalized() if dir.length() > 0.0001 else Vector2(1, 0)
		# 行走摆动相位
		var phase := anim_time * (5.0 + z.speed * 2.0) + float(z.id) * 1.7
		var bob := sin(phase * 3.0) * 2.0
		var lean := 0.12 * sin(phase * 3.0)
		var r := TILE * 0.26
		# 地面投影
		draw_ellipse_shape(wp + Vector2(0, r * 0.9), r * 0.9, r * 0.4, Color(0, 0, 0, 0.35))
		# 身体（带挤压摆动）
		var body := col.darkened(0.15)
		draw_ellipse_shape(wp + Vector2(0, -bob), r * (1.0 - lean), r * (1.0 + lean) * 1.05, body)
		draw_ellipse_shape(wp + Vector2(0, -bob - r * 0.2), r * 0.7, r * 0.7, col)
		# 头
		draw_circle(wp + facing * r * 0.7 + Vector2(0, -bob - r), r * 0.45, col.lightened(0.1))
		# 眼睛（朝向移动方向）
		var eye := wp + facing * r * 0.7 + Vector2(0, -bob - r) + facing * r * 0.2
		draw_circle(eye, r * 0.18, Color(0.05, 0.05, 0.05))
		draw_circle(eye + facing * r * 0.08, r * 0.07, Color(1, 1, 1, 0.9))
		# 手臂摆动（丧尸特征：前伸）
		var swing := sin(phase * 3.0) * 0.4
		draw_line(wp + Vector2(0, -bob), wp + facing * r * 1.2 + Vector2(0, -bob) + Vector2(-facing.y, facing.x) * swing * r, col.darkened(0.2), 3.0)
		draw_line(wp + Vector2(0, -bob), wp + facing * r * 1.2 + Vector2(0, -bob) - Vector2(-facing.y, facing.x) * swing * r, col.darkened(0.2), 3.0)
		# Spitter 吐息光
		if z.kind == Zombie.Kind.SPITTER:
			draw_circle(wp + facing * r * 1.3, r * 0.15 + sin(phase) * 1.5, Color(0.7, 0.4, 0.9, 0.6))
		# HP 条
		if z.hp < z.max_hp:
			_draw_hp_bar(wp - Vector2(r, r + 12), r * 2.0, z.hp, z.max_hp)

func _draw_bullets() -> void:
	for b: Dictionary in bullets:
		var cur: Vector2 = b["from"].lerp(b["to"], b["t"])
		# 曳光
		draw_line(b["from"], cur, COLOR_BULLET, 2.5)
		draw_circle(cur, 3.5, COLOR_BULLET)
		draw_circle(cur, 1.8, Color(1, 1, 1, 0.95))

func _draw_particles() -> void:
	for p: Dictionary in particles:
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
	# 生产房冒烟
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
	# 环境浮尘
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

func _rot_rect(c: Vector2, w: float, h: float, ang: float, col: Color) -> void:
	var hw := w / 2.0; var hh := h / 2.0
	var pts := PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	for i in pts.size():
		var p := pts[i]
		var rx := p.x * cos(ang) - p.y * sin(ang)
		var ry := p.x * sin(ang) + p.y * cos(ang)
		pts[i] = c + Vector2(rx, ry)
	_fill_poly(pts, col)

func draw_ellipse_shape(center: Vector2, rx: float, ry: float, col: Color) -> void:
	_fill_poly(_ellipse(center, rx, ry), col)

func _fill_poly(pts: PackedVector2Array, col: Color) -> void:
	draw_polygon(pts, PackedColorArray([col]))

func _ellipse(c: Vector2, rx: float, ry: float, seg: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := float(i) / seg * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _tri(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b, c])

func _hash(n: float) -> float:
	var s := sin(n * 12.9898) * 43758.5453
	return s - floor(s)

func _draw_hp_bar(origin: Vector2, width: float, hp: int, max_hp: int) -> void:
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var bar_h := 5.0
	draw_rect(Rect2(origin, Vector2(width, bar_h)), COLOR_HP_BG)
	var col := COLOR_HP_GREEN if ratio > 0.6 else (COLOR_HP_ORANGE if ratio > 0.3 else COLOR_HP_RED)
	draw_rect(Rect2(origin, Vector2(width * ratio, bar_h)), col)

func _rect_perimeter_point(rect: Rect2, t: float) -> Vector2:
	var x := rect.position.x; var y := rect.position.y
	var w := rect.size.x; var h := rect.size.y
	var per := 2.0 * (w + h)
	var d := t * per
	if d < w: return Vector2(x + d, y)
	d -= w
	if d < h: return Vector2(x + w, y + d)
	d -= h
	if d < w: return Vector2(x + w - d, y + h)
	d -= w
	return Vector2(x, y + h - d)

func _sync_state() -> void:
	update_hud()
	queue_redraw()

func update_hud() -> void:
	if hud:
		hud.set_state(sim.state, sim.wave, sim.zombies.size(), sim.scrap, sim.biomass, selected_type)

# ===================== 开发期截图 =====================
func _dev_shot_setup() -> void:
	# 自动布防：环绕核心造墙+塔，开第 1 波，0.7s 后截图（仍在战斗中）
	var c := grid.size / 2 - 1
	sim.scrap = 1000
	var layout := [
		[RoomDefs.Type.WALL, Vector2i(c - 1, c - 1)], [RoomDefs.Type.WALL, Vector2i(c, c - 1)],
		[RoomDefs.Type.WALL, Vector2i(c + 1, c - 1)], [RoomDefs.Type.WALL, Vector2i(c - 1, c)],
		[RoomDefs.Type.WALL, Vector2i(c + 1, c)], [RoomDefs.Type.WALL, Vector2i(c - 1, c + 1)],
		[RoomDefs.Type.WALL, Vector2i(c, c + 1)], [RoomDefs.Type.WALL, Vector2i(c + 1, c + 1)],
		[RoomDefs.Type.DEFENSE, Vector2i(c - 2, c - 2)], [RoomDefs.Type.DEFENSE, Vector2i(c + 2, c - 2)],
		[RoomDefs.Type.DEFENSE, Vector2i(c - 2, c + 2)], [RoomDefs.Type.DEFENSE, Vector2i(c + 2, c + 2)],
		[RoomDefs.Type.PRODUCTION, Vector2i(c, c - 2)],
	]
	for item: Array in layout:
		var tid: int = int(item[0])
		var cid: Vector2i = item[1] as Vector2i
		var id: int = sim.try_place(tid, cid)
		if id >= 0:
			grid.rooms[id]["hp"] = RoomDefs.hp(tid)
			prev_room_hp[id] = grid.rooms[id]["hp"]
	start_wave()
	await get_tree().create_timer(0.7).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("D:/SAFE/apocalypse/fortress/screenshot.png")
	get_tree().quit()
