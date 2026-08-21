extends RefCounted
class_name BattleSim

# 战斗内核（服务端权威、纯逻辑层，无节点依赖，可 headless 结算，ADR-002）
# 固定 1s tick 驱动（ADR-004 确定性：种子化 RNG + 整数化结算）
# 负责：寻路/BFS、破墙(breach)、防御房自动开火、波次消耗结算、胜负判定
#
# 坐标约定：丧尸 pos 以"单元坐标"表示（cell-center 基，即 cell(cx,cy) 中心 = (cx+0.5, cy+0.5)）。
# 渲染层（main.gd）按 TICK 间隔对 prev_pos→pos 做插值，消费本核快照（快照插值模式）。

const TICK := 1.0
const SPAWN_MARGIN := 2          # 战场环带宽度（限定 BFS 边界，防无限扩散）

# —— 战斗数值（设计提案·待平衡 pass，对齐波次 §3.4 / §5.3 / §5.4；GDD 标注待复核）——
const DEFENSE_RANGE_CELLS := 4   # 防御房射程（格）
const DEFENSE_DMG := 30          # 每 tick 防御伤害
const BREACH_DPS := 12           # 每 tick 丧尸破墙伤害
const ZOMBIE_CORE_DPS := 15      # 每 tick 丧尸对指挥核心伤害
const ROOM_COST := {             # 建造造价（废料，待平衡；引用建造 §3.3 拆除返还 α=0.5 对偶）
	RoomDefs.Type.WALL: 20,
	RoomDefs.Type.DEFENSE: 40,
	RoomDefs.Type.PRODUCTION: 30,
	RoomDefs.Type.COMMAND: 0,
}

const SOFT_CAP_SCRAP := 500       # 废料软上限（经济 §5.2，待平衡）
const SOFT_CAP_BIOMASS := 300     # 生物质软上限（经济 §5.2，待平衡）
const DEMOLISH_REFUND := 0.5      # 拆除返还 α（建造 §3.3 对偶：修复成本 0.5×造价）
const UPGRADE_COST := 15          # 升级/加固消耗（废料，待平衡）

var grid: GridModel
var zombies: Array[Zombie] = []  # 当前存活丧尸
var wave: int = 0
var level: int = 1
var state: String = "build"      # build | combat | win | fail
var scrap: int = 200
var biomass: int = 50            # 生物质（应急资源，波次消耗引用经济 §5.5）
var core_id: int = -1
var next_id: int = 0
var rng: RandomNumberGenerator

func _init(g: GridModel) -> void:
	grid = g
	rng = RandomNumberGenerator.new()
	rng.seed = 12345             # 固定种子 → 确定性回放（ADR-004）
	_refresh_core()

func _refresh_core() -> void:
	core_id = -1
	for id in grid.rooms:
		if grid.rooms[id]["type"] == RoomDefs.Type.COMMAND:
			core_id = id
			break

# —— 玩家指令（建造，服务端权威结算）——
func try_place(type: int, c: Vector2i) -> int:
	if state != "build":
		return -1
	var cost: int = ROOM_COST.get(type, 20)
	if scrap < cost:
		return -1
	var id: int = grid.place(type, c)
	if id >= 0:
		scrap -= cost
		if type == RoomDefs.Type.COMMAND:
			_refresh_core()
	return id

# —— 拆除（建造 §3.3：返还 原造价 × α=0.5；指挥核心不可拆）——
# 成功返回返还废料数（≥0）；非法（非建造态/房间不存在/是核心）返回 -1
func try_demolish(id: int) -> int:
	if state != "build":
		return -1
	if not grid.rooms.has(id):
		return -1
	if grid.rooms[id]["type"] == RoomDefs.Type.COMMAND:
		return -1
	var cost: int = ROOM_COST.get(grid.rooms[id]["type"], 20)
	var refund: int = int(cost * DEMOLISH_REFUND)
	scrap += refund
	grid.demolish(id)
	if id == core_id:
		core_id = -1
	return refund

# —— 升级/加固（建造 §3.3：消耗资源提升房间等级，不占新格）——
# 成功返回加固后 HP（≥0）；非法返回 -1
func try_upgrade(id: int) -> int:
	if state != "build":
		return -1
	if not grid.rooms.has(id):
		return -1
	if scrap < UPGRADE_COST:
		return -1
	scrap -= UPGRADE_COST
	grid.harden(id)
	return grid.rooms[id]["hp"]

# —— 波次开始：按 N(w) 生成丧尸（对齐波次 §3.3 规模公式）——
func begin_wave(w: int) -> void:
	if state != "build":
		return
	wave = w
	state = "combat"
	var n: int = WaveManager.count(w)
	for i in range(n):
		var k: int = Zombie.Kind.WALKER
		if i % 5 == 0:
			k = Zombie.Kind.RUNNER
		elif i % 7 == 0:
			k = Zombie.Kind.SPITTER
		var z := Zombie.make(k, w)
		z.id = next_id
		next_id += 1
		z.pos = _spawn_pos()
		z.prev_pos = z.pos
		zombies.append(z)

func _spawn_pos() -> Vector2:
	var edge: int = rng.randi_range(0, 3)
	var s: int = grid.size
	var r: int = rng.randi_range(0, s - 1)
	match edge:
		0: return Vector2(-0.5, r + 0.5)        # 左
		1: return Vector2(s + 0.5, r + 0.5)     # 右
		2: return Vector2(r + 0.5, -0.5)        # 上
		_: return Vector2(r + 0.5, s + 0.5)     # 下

# —— 固定 tick：推进一秒战斗结算 ——
func tick() -> void:
	if state != "combat":
		return
	for z in zombies:
		z.prev_pos = z.pos
	var dist: Dictionary = _bfs_dist_to_core()
	for z in zombies:
		_move_zombie(z, dist)
	_defense_fire()
	# 清理阵亡
	var alive: Array[Zombie] = []
	for z in zombies:
		if z.hp > 0:
			alive.append(z)
	zombies = alive
	# 胜负判定
	if core_id >= 0 and grid.rooms.has(core_id) and grid.rooms[core_id]["hp"] <= 0:
		state = "fail"
		return
	if zombies.is_empty():
		_settle_wave()

# —— 寻路：BFS 从指挥核心扩散的距离场（障碍=占据格，目标=核心）——
func _bfs_dist_to_core() -> Dictionary:
	var dist: Dictionary = {}     # Vector2i -> int
	var queue: Array = []
	if core_id >= 0 and grid.rooms.has(core_id):
		for c in grid.rooms[core_id]["cells"]:
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
	if grid.in_bounds(n):
		return not grid.occupied.has(n)
	# 网格外仅允许战场环带（限定 BFS 边界）
	var m: int = SPAWN_MARGIN
	return n.x >= -m and n.x < grid.size + m and n.y >= -m and n.y < grid.size + m

func _neighbors(c: Vector2i) -> Array:
	return [
		Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y),
		Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)
	]

func _is_core_cell(c: Vector2i) -> bool:
	if core_id < 0:
		return false
	return _cell_in_cells(c, grid.rooms[core_id]["cells"])

func _cell_in_cells(c: Vector2i, cells: Array) -> bool:
	for cc in cells:
		if cc == c:
			return true
	return false

# —— 单只丧尸推进：沿距离场向核心移动；受阻则破墙/攻核心 ——
func _move_zombie(z: Zombie, dist: Dictionary) -> void:
	var cur: Vector2i = Vector2i(floor(z.pos.x), floor(z.pos.y))
	# 已身处核心格 → 直接攻核心
	if _is_core_cell(cur):
		_damage_core(ZOMBIE_CORE_DPS)
		return
	var best: Vector2i = cur
	var best_d: int = dist.get(cur, 0x7FFFFFFF)
	var best_is_core: bool = false
	for n in _neighbors(cur):
		var dd: int = dist.get(n, 0x7FFFFFFF)
		if dd < best_d:
			best_d = dd
			best = n
			best_is_core = _is_core_cell(n)
	if best == cur:
		_breach_or_attack(z, cur)
		return
	if best_is_core:
		_damage_core(ZOMBIE_CORE_DPS)
		return
	# 朝目标格中心移动（每 tick 走 speed 格，cell 基）
	var target := Vector2(best.x + 0.5, best.y + 0.5)
	var to: Vector2 = target - z.pos
	var len: float = to.length()
	if len <= z.speed:
		z.pos = target
	else:
		z.pos += to.normalized() * z.speed

# 受阻时：优先攻击相邻核心；否则破"距核心最近"的阻挡格（HP 归零→breach 变为可通行）
func _breach_or_attack(z: Zombie, cur: Vector2i) -> void:
	var target: Vector2i = cur
	var target_d: float = INF
	var target_is_core: bool = false
	var cc := _core_center()
	for n in _neighbors(cur):
		if _is_core_cell(n):
			target = n
			target_is_core = true
			target_d = 0.0
			break
		if grid.in_bounds(n) and grid.occupied.has(n):
			var dd: float = cc.distance_to(Vector2(n.x + 0.5, n.y + 0.5))
			if dd < target_d:
				target_d = dd
				target = n
				target_is_core = false
	if target_is_core:
		_damage_core(ZOMBIE_CORE_DPS)
		return
	if target != cur:
		var rid: int = grid.occupied[target]
		grid.rooms[rid]["hp"] -= BREACH_DPS
		if grid.rooms[rid]["hp"] <= 0:
			grid.demolish(rid)
			if rid == core_id:
				core_id = -1

func _core_center() -> Vector2:
	if core_id < 0 or not grid.rooms.has(core_id):
		return Vector2(grid.size * 0.5, grid.size * 0.5)
	return _room_center(grid.rooms[core_id])

func _damage_core(dmg: int) -> void:
	if core_id < 0 or not grid.rooms.has(core_id):
		return
	grid.rooms[core_id]["hp"] -= dmg

# —— 防御房自动开火：每 tick 命中射程内最近丧尸 ——
func _defense_fire() -> void:
	for id in grid.rooms:
		var r: Dictionary = grid.rooms[id]
		if r["type"] != RoomDefs.Type.DEFENSE:
			continue
		var center := _room_center(r)
		var target: Zombie = null
		var best_d: float = INF
		for z in zombies:
			var d: float = center.distance_to(z.pos)
			if d <= DEFENSE_RANGE_CELLS and d < best_d:
				best_d = d
				target = z
		if target != null:
			target.hp -= DEFENSE_DMG

func _room_center(r: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	for c in r["cells"]:
		sum += Vector2(c.x + 0.5, c.y + 0.5)
	return sum / r["cells"].size()

# —— 波次结算：消耗（逐字引用经济 §5.5 / 波次 §3.5）+ 成功奖励 + 等级成长 ——
func _settle_wave() -> void:
	var ammo: int = AmmoCost(wave)    # 废料（弹药）
	var bio: int = BioCost(wave)      # 生物质（应急）
	scrap = max(0, scrap - ammo)
	biomass = max(0, biomass - bio)
	# 成功抵御奖励（基线随 w，待平衡；维持经济可继续扩张）
	scrap += 15
	biomass += 5
	# 资源软上限（经济 §5.2）：结算后钳制，超出部分丢弃（仓储提升上限留待 Phase D）
	scrap = min(scrap, SOFT_CAP_SCRAP)
	biomass = min(biomass, SOFT_CAP_BIOMASS)
	# 成长：每存活 3 波堡垒等级 +1（引用概念 §8.2 / 建造 §5.2）
	if wave % 3 == 0 and level < 6:
		level += 1
		grid.set_level(level)
	if wave >= 10:
		state = "win"
	else:
		state = "build"

# 波次消耗公式（逐字引用经济 §5.5 / 波次 §5.4）
static func AmmoCost(w: int) -> int:
	return roundi(20 * (1.0 + 0.08 * (w - 1)))

static func BioCost(w: int) -> int:
	return roundi(10 * (1.0 + 0.05 * (w - 1)))
