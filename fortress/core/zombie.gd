extends RefCounted
class_name Zombie

# 丧尸实体（对齐《波次系统 GDD》§3.2 首发三类）
enum Kind { WALKER, RUNNER, SPITTER }

var kind: int = Kind.WALKER
var hp: int = 100
var pos: Vector2 = Vector2.ZERO
var speed: float = 20.0

static func make(kind: int) -> Zombie:
	var z = Zombie.new()
	z.kind = kind
	match kind:
		Kind.WALKER:
			z.hp = 100
			z.speed = 20.0
		Kind.RUNNER:
			z.hp = 60
			z.speed = 45.0
		Kind.SPITTER:
			z.hp = 80
			z.speed = 15.0
	return z

static func texture(kind: int) -> Texture2D:
	match kind:
		Kind.WALKER: return preload("res://assets/sprites/zombie_walker.png")
		Kind.RUNNER: return preload("res://assets/sprites/zombie_runner.png")
		Kind.SPITTER: return preload("res://assets/sprites/zombie_spitter.png")
	return preload("res://assets/sprites/zombie_walker.png")
