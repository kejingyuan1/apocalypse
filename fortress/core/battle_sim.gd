extends RefCounted

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const Zombie := preload("res://core/zombie.gd")

# 末日堡垒 · COC 式进攻玩法（服务端权威逻辑层，ADR-002）
# 玩家带一支部队，从地图任意空白格下兵，攻打敌方基地。
# 敌方基地 = 房间(建筑) + COC 式城墙(高血量阻挡) + 自动开火的防御塔。
# 胜负：摧毁敌方指挥核心(胜)；部队全灭且无可部署单位(负)。

const TICK := 1.0
const GRID_SIZE := 120           # 整体战场（含外围部署区）
const BASE_REGION := 100         # 敌方基地占据区域（居中）
const BASE_OFFSET := (GRID_SIZE - BASE_REGION) / 2   # = 10
const WALL_HALF := 20            # 外墙半边长（外墙 40x40）
const DEFENSE_RANGE_CELLS := 4
const DEFENSE_DMG := 16
const UNIT_DMG := 30              # 进攻单位每 tick 对建筑伤害

# 玩家初始部队（COC 式兵种配额）
const ARMY := {
	Zombie.Kind.WALKER: 36,
	Zombie.Kind.RUNNER: 14,
	Zombie.Kind.SPITTER: 8,
}

var grid: GridModel
var units: Array = []            # 玩家部队（存活）
var army: Dictionary = {}        # 待部署剩余：kind -> count
var state: String = "deploy"     # deploy | combat | win | fail
var core_id: int = -1
var next_id: int = 0
var blocked_deploy: Dictionary = {}   # Vector2i -> true：建筑笼罩范围内禁止敌方下兵
var rng: RandomNumberGenerator

# —— 动画/渲染事件（服务端权威产出，客户端消费做子弹/粒子，不回写逻辑）——
var fire_events: Array = []      # 本 tick 防御开火：{from:Vector2(单元), to:Vector2(单元), dmg:int}
var hit_events: Array = []       # 本 tick 命中（进攻单位受击）：{pos:Vector2(单元), dmg:int}
var building_hit_events: Array = [] # 本 tick 建筑受击：{pos:Vector2(单元), dmg:int}
var total_shots: int = 0         # 累计开火数（验证用）
var army_total: int = 0          # 初始总兵力
var waypoints: Array = []        # Vector2 路径点（单元坐标），部队优先前往

func _init(g: GridModel) -> void:
	grid = g
	if g.size != GRID_SIZE:
		g.size = GRID_SIZE
	rng = RandomNumberGenerator.new()
	rng.seed = 12345
	army = {}
	for k in ARMY.keys():
		army[k] = ARMY[k]
		army_total += ARMY[k]
	_build_enemy_base()

# —— 敌方基地生成（COC 式：核心 + 防御塔 + 生产房；城墙由玩家在编辑器中自行摆放）——
# 基地占据 BASE_REGION(100) 居中区域。进攻时若玩家已保存布局则加载，否则使用此默认非城墙布局。
func _build_enemy_base() -> void:
	var mid: int = BASE_OFFSET + int(BASE_REGION / 2)   # 60（基地区域中心）
	# 核心 2x2，正中
	core_id = grid.place(RoomDefs.Type.COMMAND, Vector2i(mid - 1, mid - 1))
	# 防御塔：核心四角保护
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid - 6, mid - 6))
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid + 5, mid - 6))
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid - 6, mid + 5))
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid + 5, mid + 5))
	# 生产房：核心四边中点
	grid.place(RoomDefs.Type.PRODUCTION, Vector2i(mid - 1, mid - 6))
	grid.place(RoomDefs.Type.PRODUCTION, Vector2i(mid - 1, mid + 5))
	grid.place(RoomDefs.Type.PRODUCTION, Vector2i(mid - 6, mid - 1))
	grid.place(RoomDefs.Type.PRODUCTION, Vector2i(mid + 5, mid - 1))
	# 标记笼罩范围：每个房间外扩 1 格禁止敌方下兵（COC 式建筑保护范围）
	_rebuild_deploy_blocked()

# —— 布局导出/加载（基地编辑器 + PVP 保存）——
func export_layout() -> Dictionary:
	var rooms: Array = []
	for id: int in grid.rooms:
		var r: Dictionary = grid.rooms[id]
		rooms.append({
			"type": int(r["type"]),
			"origin": {"x": int(r["origin"].x), "y": int(r["origin"].y)},
			"level": r.get("level", 0),
		})
	return {"version": 2, "grid_size": grid.size, "rooms": rooms}

func load_layout(layout: Dictionary) -> bool:
	if not layout.has("rooms"):
		return false
	# 清空现有房间（保留网格尺寸）
	for id: int in grid.rooms.keys():
		grid.demolish(id)
	core_id = -1
	# 按顺序放置，确保核心存在
	var rooms: Array = layout["rooms"]
	for entry: Dictionary in rooms:
		var t: int = int(entry["type"])
		var ox: int = int(entry["origin"]["x"])
		var oy: int = int(entry["origin"]["y"])
		var lv: int = entry.get("level", 0)
		var id: int = grid.place(t, Vector2i(ox, oy), lv)
		if id >= 0 and t == RoomDefs.Type.COMMAND:
			core_id = id
	_rebuild_deploy_blocked()
	return true

# 升级指定城墙（COC 式）
func upgrade_wall(id: int) -> bool:
	if not grid.rooms.has(id):
		return false
	if grid.rooms[id]["type"] != RoomDefs.Type.WALL:
		return false
	var ok: bool = grid.upgrade(id)
	if ok:
		_rebuild_deploy_blocked()
	return ok

func _rebuild_deploy_blocked() -> void:
	blocked_deploy.clear()
	for rid in grid.rooms:
		for c in grid.rooms[rid]["cells"]:
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					blocked_deploy[Vector2i(c.x + dx, c.y + dy)] = true

# —— 玩家下兵：在空白格部署一只指定兵种（进攻方）——
# 成功返回 true；非法（非部署态/兵力耗尽/越界/占用）返回 false
func deploy(kind: int, c: Vector2i) -> bool:
	if state != "deploy" and state != "combat":
		return false
	if not army.has(kind) or army[kind] <= 0:
		return false
	if not grid.in_bounds(c):
		return false
	if grid.occupied.has(c):
		return false
	if blocked_deploy.has(c):
		return false
	var z: RefCounted = Zombie.make(kind, 1)
	z.id = next_id
	next_id += 1
	z.pos = Vector2(c.x + 0.5, c.y + 0.5)
	z.prev_pos = z.pos
	units.append(z)
	army[kind] -= 1
	if state == "deploy":
		state = "combat"
	return true

func army_left() -> int:
	var n: int = 0
	for v in army.values():
		n += v
	return n

func set_waypoints(pts: Array) -> void:
	waypoints = []
	for p in pts:
		waypoints.append(Vector2(p.x, p.y))

func clear_waypoints() -> void:
	waypoints = []

# —— 固定 tick：推进一秒战斗结算 ——
func tick() -> void:
	if state != "combat":
		return
	fire_events.clear()
	hit_events.clear()
	building_hit_events.clear()
	for u in units:
		u.prev_pos = u.pos
	var dist: Dictionary = _bfs_dist_to_buildings()
	for u in units:
		_move_unit(u, dist)
	_defense_fire()
	# 清理阵亡
	var alive: Array = []
	for u in units:
		if u.hp > 0:
			alive.append(u)
	units = alive
	# 胜负判定（核心被摧毁后 demolish 会把 core_id 置 -1，故同时判定两种情形）
	if core_id < 0 or (core_id >= 0 and grid.rooms.has(core_id) and grid.rooms[core_id]["hp"] <= 0):
		state = "win"
		return
	if units.is_empty() and army_left() <= 0:
		state = "fail"

# —— 多源 BFS：从所有建筑(含城墙)扩散距离场，供进攻单位寻找最近目标 ——
func _bfs_dist_to_buildings() -> Dictionary:
	var dist: Dictionary = {}     # Vector2i -> int
	var queue: Array = []
	for id in grid.rooms:
		for c in grid.rooms[id]["cells"]:
			dist[c] = 0
			queue.append(c)
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		for n in _neighbors(cur):
			if dist.has(n):
				continue
			if not _passable(n):
				continue
			dist[n] = d + 1
			queue.append(n)
	return dist

func _passable(n: Vector2i) -> bool:
	if not grid.in_bounds(n):
		return false
	return not grid.occupied.has(n)

func _neighbors(c: Vector2i) -> Array:
	return [
		Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y),
		Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)
	]

# —— 单只进攻单位：相邻有建筑则攻击最薄弱者；否则沿距离场向最近建筑推进 ——
func _move_unit(u: RefCounted, dist: Dictionary) -> void:
	var cur: Vector2i = Vector2i(floor(u.pos.x), floor(u.pos.y))
	# 1. 相邻有建筑 → 攻击最薄弱者（城墙/塔/核心均可被拆）
	var atk_cell: Vector2i = Vector2i(-1, -1)
	var atk_hp: int = 2147483647
	for n in _neighbors(cur):
		if grid.occupied.has(n):
			var rid: int = grid.occupied[n]
			var hp: int = grid.rooms[rid]["hp"]
			if hp < atk_hp:
				atk_hp = hp
				atk_cell = n
	if atk_cell != Vector2i(-1, -1):
		var rid: int = grid.occupied[atk_cell]
		grid.rooms[rid]["hp"] -= UNIT_DMG
		building_hit_events.append({"pos": Vector2(atk_cell.x + 0.5, atk_cell.y + 0.5), "dmg": UNIT_DMG})
		if grid.rooms[rid]["hp"] <= 0:
			grid.demolish(rid)
			if rid == core_id:
				core_id = -1
		return
	# 2. 若有路径点，优先朝当前路径点移动
	if u.waypoint_idx >= 0 and waypoints.size() > 0:
		if u.waypoint_idx >= waypoints.size():
			u.waypoint_idx = -1
		else:
			var wp: Vector2 = waypoints[u.waypoint_idx]
			if u.pos.distance_to(wp) < 1.0:
				u.waypoint_idx += 1
				if u.waypoint_idx >= waypoints.size():
					u.waypoint_idx = -1
				else:
					wp = waypoints[u.waypoint_idx]
			if u.waypoint_idx >= 0:
				var best_wp: Vector2i = cur
				var best_wd: float = cur.distance_squared_to(wp)
				for n: Vector2i in _neighbors(cur):
					if grid.occupied.has(n):
						continue
					var dd: float = n.distance_squared_to(wp)
					if dd < best_wd:
						best_wd = dd
						best_wp = n
				if best_wp != cur:
					var target_wp: Vector2 = Vector2(best_wp.x + 0.5, best_wp.y + 0.5)
					var to_wp: Vector2 = target_wp - u.pos
					if to_wp.length() <= u.speed:
						u.pos = target_wp
					else:
						u.pos += to_wp.normalized() * u.speed
				return
	# 3. 朝最近建筑移动
	var best: Vector2i = cur
	var best_d: int = dist.get(cur, 2147483647)
	for n in _neighbors(cur):
		if grid.occupied.has(n):
			continue
		var dd: int = dist.get(n, 2147483647)
		if dd < best_d:
			best_d = dd
			best = n
	if best == cur:
		return
	var target: Vector2 = Vector2(best.x + 0.5, best.y + 0.5)
	var to: Vector2 = target - u.pos
	var len: float = to.length()
	if len <= u.speed:
		u.pos = target
	else:
		u.pos += to.normalized() * u.speed

# —— 防御塔自动开火：每 tick 命中射程内最近进攻单位 ——
func _defense_fire() -> void:
	for id in grid.rooms:
		var r: Dictionary = grid.rooms[id]
		if r["type"] != RoomDefs.Type.DEFENSE:
			continue
		var center := _room_center(r)
		var target = null
		var best_d: float = INF
		for u in units:
			var d: float = center.distance_to(u.pos)
			if d <= DEFENSE_RANGE_CELLS and d < best_d:
				best_d = d
				target = u
		if target != null:
			target.hp -= DEFENSE_DMG
			fire_events.append({"from": center, "to": target.pos, "dmg": DEFENSE_DMG})
			hit_events.append({"pos": target.pos, "dmg": DEFENSE_DMG})
			total_shots += 1

func _room_center(r: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for c in r["cells"]:
		sum += Vector2(c.x + 0.5, c.y + 0.5)
	return sum / r["cells"].size()
