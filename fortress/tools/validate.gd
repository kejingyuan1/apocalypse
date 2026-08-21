extends SceneTree

# 无头校验脚本（仅开发期用，不进正式构建）：
# 1) 强制预编译并加载全部 core 脚本，并显式 preload main.gd / hud.gd 以校验其可编译
# 2) 跑通一整波战斗（BFS 寻路 + 防御开火 + 波次结算）
# 3) 校验确定性（ADR-004：同种子两次模拟结果一致）
# 4) 校验破墙(breach) 路径不崩
# 5) 校验 Phase C：拆除返还 / 指挥核心不可拆 / 资源软上限钳制
# 结果同时 print 到终端（需本地控制台运行）并写入 user://validate_result.txt

# 注意：所有 core 脚本均不使用 class_name，改用显式 preload，避免 .godot/ 缓存缺失时 headless 无法解析。
const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Zombie := preload("res://core/zombie.gd")

const RESULT := "user://validate_result.txt"

# 显式预编译渲染层脚本（main.gd / hud.gd），确保整工程可构建
const _MAIN_SCRIPT := preload("res://main.gd")
const _HUD_SCRIPT := preload("res://hud.gd")

func _init() -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f == null:
		push_error("cannot open result file (results will only print to console)")
	_emit(f, "VALIDATE_START godot=" + str(Engine.get_version_info()["string"]) + " main_ok=" + str(_MAIN_SCRIPT != null) + " hud_ok=" + str(_HUD_SCRIPT != null))

	# —— 场景 A：基础闭环（建造+防御开火+结算）——
	var g := GridModel.new()
	g.set_level(3)
	g.place(RoomDefs.Type.COMMAND, Vector2i(0, 0))
	var sim := BattleSim.new(g)
	sim.try_place(RoomDefs.Type.DEFENSE, Vector2i(5, 5))
	sim.try_place(RoomDefs.Type.WALL, Vector2i(4, 0))
	sim.try_place(RoomDefs.Type.WALL, Vector2i(0, 4))
	sim.begin_wave(1)
	var n0 := sim.zombies.size()
	var ticks := 0
	while sim.state == "combat" and ticks < 400:
		sim.tick()
		ticks += 1
	var core_hp_a := -1
	if sim.core_id >= 0 and g.rooms.has(sim.core_id):
		core_hp_a = g.rooms[sim.core_id]["hp"]
	_emit(f, "A spawn=%d wave=%d state=%s ticks=%d zombies_left=%d scrap=%d biomass=%d core_hp=%d" % [
		n0, sim.wave, sim.state, ticks, sim.zombies.size(), sim.scrap, sim.biomass, core_hp_a])

	# —— 确定性（同种子两遍一致）——
	var sim2 := _fresh_sim()
	for i in 20:
		sim2.tick()
	var h1 := _hash_zombies(sim2.zombies)
	var sim3 := _fresh_sim()
	for i in 20:
		sim3.tick()
	var h2 := _hash_zombies(sim3.zombies)
	_emit(f, "DETERMINISTIC=" + ("true" if h1 == h2 else "false"))

	# —— 场景 B：破墙（2x2 核心被城墙环完全包围，强制 breach）——
	var g4 := GridModel.new()
	g4.set_level(3)
	g4.place(RoomDefs.Type.COMMAND, Vector2i(3, 3))
	var sim4 := BattleSim.new(g4)
	sim4.scrap = 1000  # 确保环能闭合（12 块墙 × 20 = 240）
	# 4x4 城墙环，把 (3,3)-(4,4) 的 2x2 核心围在正中间
	for y in range(2, 6):
		sim4.try_place(RoomDefs.Type.WALL, Vector2i(2, y))
		sim4.try_place(RoomDefs.Type.WALL, Vector2i(5, y))
	for x in range(3, 5):
		sim4.try_place(RoomDefs.Type.WALL, Vector2i(x, 2))
		sim4.try_place(RoomDefs.Type.WALL, Vector2i(x, 5))
	var walls_before := _count_type(g4, RoomDefs.Type.WALL)
	sim4.begin_wave(1)
	var t2 := 0
	while sim4.state == "combat" and t2 < 800:
		sim4.tick()
		t2 += 1
	var core_hp_b := -1
	if sim4.core_id >= 0 and g4.rooms.has(sim4.core_id):
		core_hp_b = g4.rooms[sim4.core_id]["hp"]
	_emit(f, "B walls_before=%d walls_after=%d wave=%d state=%s ticks=%d core_hp=%d" % [
		walls_before, _count_type(g4, RoomDefs.Type.WALL), sim4.wave, sim4.state, t2, core_hp_b])

	# —— 场景 C：拆除返还 + 指挥核心不可拆 + 资源软上限钳制（Phase C）——
	var g5 := GridModel.new()
	g5.set_level(3)
	g5.place(RoomDefs.Type.COMMAND, Vector2i(0, 0))
	var sim5 := BattleSim.new(g5)
	var before := sim5.scrap
	var did := sim5.try_place(RoomDefs.Type.DEFENSE, Vector2i(5, 5))   # 造价 40
	var cost_paid := before - sim5.scrap
	var refund := sim5.try_demolish(did)                               # 返还 floor(40*0.5)=20
	var after_demo := sim5.scrap
	var cmd_guard := sim5.try_demolish(sim5.core_id)                   # 指挥核心应返回 -1
	# 软上限：强制超上限后做结算，应被钳到 SOFT_CAP
	sim5.wave = 1
	sim5.scrap = 100000
	sim5.biomass = 100000
	sim5._settle_wave()
	_emit(f, "C cost_paid=%d refund=%d after_demo=%d cmd_guard_ok=%s cap_scrap=%d cap_biomass=%d" % [
		cost_paid, refund, after_demo, "true" if cmd_guard == -1 else "false",
		sim5.scrap, sim5.biomass])

	# —— 场景 D：可赢性探针（合理布防应能守住第 1 波，核心存活）——
	var g6 := GridModel.new()
	g6.set_level(1)
	g6.place(RoomDefs.Type.COMMAND, Vector2i(2, 2))
	var sim6 := BattleSim.new(g6)
	# 用 200 废料造 5 座 1x1 防御塔，环绕 2x2 核心
	var towers := [Vector2i(0, 4), Vector2i(1, 4), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 4)]
	var placed_towers := 0
	for c in towers:
		if sim6.try_place(RoomDefs.Type.DEFENSE, c) >= 0:
			placed_towers += 1
	sim6.begin_wave(1)
	var t3 := 0
	while sim6.state == "combat" and t3 < 400:
		sim6.tick()
		t3 += 1
	var core_hp_d := -1
	if sim6.core_id >= 0 and g6.rooms.has(sim6.core_id):
		core_hp_d = g6.rooms[sim6.core_id]["hp"]
	_emit(f, "D placed_towers=%d wave=%d state=%s ticks=%d core_hp=%d zombies_left=%d" % [
		placed_towers, sim6.wave, sim6.state, t3, core_hp_d, sim6.zombies.size()])

	_emit(f, "VALIDATE_OK")
	f.close()
	quit()

func _emit(f: FileAccess, msg: String) -> void:
	print(msg)
	if f != null:
		f.store_line(msg)

func _fresh_sim() -> BattleSim:
	var g := GridModel.new()
	g.set_level(3)
	g.place(RoomDefs.Type.COMMAND, Vector2i(0, 0))
	var s := BattleSim.new(g)
	s.try_place(RoomDefs.Type.DEFENSE, Vector2i(5, 5))
	s.begin_wave(1)
	return s

func _hash_zombies(zs: Array) -> String:
	var s := ""
	for z in zs:
		s += "%d:%.3f,%.3f,%d|" % [z.id, z.pos.x, z.pos.y, z.hp]
	return s

func _count_type(g: GridModel, t: int) -> int:
	var c := 0
	for id in g.rooms:
		if g.rooms[id]["type"] == t:
			c += 1
	return c
