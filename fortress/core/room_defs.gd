extends RefCounted
# 注意：不使用 class_name，避免 .godot/ 缓存缺失时 headless 无法解析全局类名。
# 引用本脚本处请用 const RoomDefs := preload("res://core/room_defs.gd")

# 房间类型定义（对齐《建造系统 GDD》§7 面积矩阵）
enum Type { WALL, DEFENSE, PRODUCTION, COMMAND }

# 面积（格）：城墙1x1 / 防御3x3 / 生产3x2 / 指挥4x4
static func size(type: int) -> Vector2i:
	match type:
		Type.WALL: return Vector2i(1, 1)
		Type.DEFENSE: return Vector2i(3, 3)
		Type.PRODUCTION: return Vector2i(3, 2)
		Type.COMMAND: return Vector2i(4, 4)
	return Vector2i(1, 1)

# 承伤 HP（对齐《波次系统 GDD》§5.3 HP 表）
static func hp(type: int) -> int:
	match type:
		Type.WALL: return 120
		Type.DEFENSE: return 300
		Type.PRODUCTION: return 200
		Type.COMMAND: return 600   # 对齐《波次系统 GDD》§5.3 指挥核心 HP
	return 100

# 对应像素精灵（美术圣经调色板）
static func texture(type: int) -> Texture2D:
	# 用 load 替代 preload，避免 headless/首次导入无 .import 时编译期崩溃
	match type:
		Type.WALL: return load("res://assets/art/tile_wall.png")
		Type.DEFENSE: return load("res://assets/art/room_defense.png")
		Type.PRODUCTION: return load("res://assets/art/room_production.png")
		Type.COMMAND: return load("res://assets/art/room_command.png")
	return load("res://assets/art/tile_wall.png")
