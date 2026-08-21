extends RefCounted

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const Zombie := preload("res://core/zombie.gd")

# 末日堡垒 · COC 式进攻玩法（服务端权威逻辑层，ADR-002）
# 玩家带一支部队，从地图任意空白格下兵，攻打敌方基地。
# 敌方基地 = 房间(建筑) + COC 式城墙(高血量阻挡) + 自动开火的防御塔。
# 胜负：摧毁敌方指挥核心(胜)；部队全灭且无可部署单位(负)。

const TICK := 1.0
const GRID_SIZE := 20
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
var rng: RandomNumberGenerator

# —— 动画/渲染事件（服务端权威产出，客户端消费做子弹/粒子，不回写逻辑）——
var fire_events: Array = []      # 本 tick 防御开火：{from:Vector2(单元), to:Vector2(单元)}
var hit_events: Array = []       # 本 tick 命中（进攻单位受击）位置 Vector2(单元)
var total_shots: int = 0         # 累计开火数（验证用）
var army_total: int = 0          # 初始总兵力

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

# —— 敌方基地生成（COC 式：核心居中 + 城墙闭环 + 防御塔 + 生产房）——
func _build_enemy_base() -> void:
	var s: int = GRID_SIZE
	var mid: int = int(s / 2)
	# 核心 2x2，正中
	core_id = grid.place(RoomDefs.Type.COMMAND, Vector2i(mid - 1, mid - 1))
	# 城墙闭环（围出内部空间，迫使进攻方破墙）—— COC 式城墙
	var lo: int = mid - 5
	var hi: int = mid + 4
	for x in range(lo, hi + 1):
		grid.place(RoomDefs.Type.WALL, Vector2i(x, lo))
		grid.place(RoomDefs.Type.WALL, Vector2i(x, hi))
	for y in range(lo + 1, hi):
		grid.place(RoomDefs.Type.WALL, Vector2i(lo, y))
		grid.place(RoomDefs.Type.WALL, Vector2i(hi, y))
	# 内部四角防御塔（保护核心）
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid - 4, mid))
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid + 3, mid))
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid, mid - 4))
	grid.place(RoomDefs.Type.DEFENSE, Vector2i(mid, mid + 3))
	# 内部生产房（两侧）
	grid.place(RoomDefs.Type.PRODUCTION, Vector2i(mid - 4, mid - 4))
	grid.place(RoomDefs.Type.PRODUCTION, Vector2i(mid + 1, mid + 1))

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

# —— 固定 tick：推进一秒战斗结算 ——
func tick() -> void:
	if state != "combat":
		return
	fire_events.clear()
	hit_events.clear()
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
		if grid.rooms[rid]["hp"] <= 0:
			grid.demolish(rid)
			if rid == core_id:
				core_id = -1
		return
	# 2. 朝最近建筑移动
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
			fire_events.append({"from": center, "to": target.pos})
			hit_events.append(target.pos)
			total_shots += 1

func _room_center(r: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for c in r["cells"]:
		sum += Vector2(c.x + 0.5, c.y + 0.5)
	return sum / r["cells"].size()
