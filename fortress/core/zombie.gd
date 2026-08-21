extends RefCounted
class_name Zombie

# 丧尸实体（对齐《波次系统 GDD》§3.2 首发三类 + §3.3 / §5.2 公式）
enum Kind { WALKER, RUNNER, SPITTER }

const BASE_SPEED := 20.0       # px/s（Walker 基准，待平衡 pass）
const HP_BASE := 20
const HP_GROWTH := 0.15        # 每波 +15%（波次 §3.3）

var id: int = -1
var kind: int = Kind.WALKER
var hp: int = 20
var max_hp: int = 20
var pos: Vector2 = Vector2.ZERO       # 单元坐标（cell-center 基），由战斗核推进
var prev_pos: Vector2 = Vector2.ZERO  # 上一 tick 位置，供插值渲染
var speed: float = BASE_SPEED

# HP 类型系数（逐字引用概念 §9.1 / 波次 §3.2 类型系数）
static func _hp_coef(kind: int) -> float:
	match kind:
		Kind.WALKER: return 1.0
		Kind.RUNNER: return 0.8
		Kind.SPITTER: return 1.3
		_: return 1.0

# 移动速度系数（波次 §5.2：相对 Walker=1.0）
static func _speed_coef(kind: int) -> float:
	match kind:
		Kind.WALKER: return 1.0
		Kind.RUNNER: return 1.8
		Kind.SPITTER: return 0.9
		_: return 1.0

# 按波次公式化生成（对齐波次 §3.3：HP(w)=20×(1+0.15(w−1))×类型系数）
static func make(kind: int, wave: int) -> Zombie:
	var z = Zombie.new()
	z.kind = kind
	z.max_hp = roundi(HP_BASE * (1.0 + HP_GROWTH * (wave - 1)) * _hp_coef(kind))
	z.hp = z.max_hp
	z.speed = BASE_SPEED * _speed_coef(kind)
	return z

static func texture(kind: int) -> Texture2D:
	match kind:
		Kind.WALKER: return preload("res://assets/art/zombie_walker.png")
		Kind.RUNNER: return preload("res://assets/art/zombie_runner.png")
		Kind.SPITTER: return preload("res://assets/art/zombie_spitter.png")
	return preload("res://assets/art/zombie_walker.png")
