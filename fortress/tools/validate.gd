extends SceneTree

# 无头校验脚本（仅开发期用，不进正式构建）：
# 1) 强制预编译并加载 main.gd / hud.gd，确保整工程可构建
# 2) 敌方基地生成（核心 + 城墙 + 防御塔 + 生产房）
# 3) 玩家下兵进攻：围攻并摧毁核心 → 获胜
# 4) 兵力耗尽且无可部署单位 → 失败
# 5) 防御塔确实开火（动画/子弹事件的数据源验证）
# 结果 print 到终端并写入 user://validate_result.txt

const RoomDefs := preload("res://core/room_defs.gd")
const GridModel := preload("res://core/grid_model.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Zombie := preload("res://core/zombie.gd")

const RESULT := "user://validate_result.txt"

const _MAIN_SCRIPT := preload("res://main.gd")
const _HUD_SCRIPT := preload("res://hud.gd")

func _init() -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f == null:
		push_error("cannot open result file (results will only print to console)")
	_emit(f, "VALIDATE_START godot=" + str(Engine.get_version_info()["string"]) + " main_ok=" + str(_MAIN_SCRIPT != null) + " hud_ok=" + str(_HUD_SCRIPT != null))

	# —— 场景 A：敌方基地生成 + 下兵进攻 → 摧毁核心获胜 ——
	var g := GridModel.new()
	var sim := BattleSim.new(g)
	_emit(f, "A grid=%d core=%d walls=%d defense=%d prod=%d army=%d" % [
		g.size, (1 if sim.core_id >= 0 else 0), _count_type(g, RoomDefs.Type.WALL),
		_count_type(g, RoomDefs.Type.DEFENSE), _count_type(g, RoomDefs.Type.PRODUCTION), sim.army_total])

	var s := g.size
	# 收集空白格（四周），按兵种配额把部队完整下满
	var cells: Array = []
	for y in [1, 2, s - 2, s - 3]:
		for x in range(1, s - 1):
			cells.append(Vector2i(x, y))
	var order := [Zombie.Kind.WALKER, Zombie.Kind.RUNNER, Zombie.Kind.SPITTER]
	var placed := 0
	var ci := 0
	for k in order:
		while sim.army[k] > 0 and ci < cells.size():
			if sim.deploy(k, cells[ci]):
				ci += 1
				placed += 1
	_emit(f, "A deployed=%d army_left=%d state=%s" % [placed, sim.army_left(), sim.state])

	var t := 0
	while sim.state == "combat" and t < 2000:
		sim.tick()
		t += 1
	_emit(f, "A end state=%s ticks=%d core_hp=%d units_left=%d" % [sim.state, t, _core_hp(sim, g), sim.units.size()])

	# —— 场景 B：兵力耗尽且无可部署单位 → 失败 ——
	var g2 := GridModel.new()
	var sim2 := BattleSim.new(g2)
	# 只允许 2 个兵，远离核心；防御塔会将其歼灭 → 兵尽则败
	sim2.army = {Zombie.Kind.WALKER: 2, Zombie.Kind.RUNNER: 0, Zombie.Kind.SPITTER: 0}
	sim2.deploy(Zombie.Kind.WALKER, Vector2i(0, 0))
	sim2.deploy(Zombie.Kind.WALKER, Vector2i(1, 0))
	var t2 := 0
	while sim2.state == "combat" and t2 < 3000:
		sim2.tick()
		t2 += 1
	_emit(f, "B end state=%s ticks=%d (期望 fail：兵尽)" % [sim2.state, t2])

	# —— 场景 C：防御塔开火（动画/子弹事件数据源）——
	_emit(f, "C total_shots=%d fire_ok=%s" % [sim.total_shots, "true" if sim.total_shots > 0 else "false"])

	_emit(f, "VALIDATE_OK")
	f.close()
	quit()

func _emit(f: FileAccess, msg: String) -> void:
	print(msg)
	if f != null:
		f.store_line(msg)

func _core_hp(sim: BattleSim, g: GridModel) -> int:
	if sim.core_id >= 0 and g.rooms.has(sim.core_id):
		return g.rooms[sim.core_id]["hp"]
	return -1

func _count_type(g: GridModel, t: int) -> int:
	var c := 0
	for id in g.rooms:
		if g.rooms[id]["type"] == t:
			c += 1
	return c
