extends RefCounted
# 注意：不使用 class_name，避免 .godot/ 缓存缺失时 headless 无法解析全局类名。
# 引用本脚本处请用 const RoomDefs := preload("res://core/room_defs.gd")

# 房间类型定义（对齐《建造系统 GDD》§7 面积矩阵）
enum Type { WALL, DEFENSE, PRODUCTION, COMMAND }

# 面积（格）：城墙1x1 / 防御1x1（炮塔） / 生产2x1 / 指挥2x2
# 注：原 GDD 矩阵（指挥4x4 / 防御3x3 / 生产3x2）与 Lv1=6 网格几何冲突（放不下任何防御/生产房），
# 故缩小为可放进 6×6 初始网格的尺寸，保留概念 intent。
static func size(type: int) -> Vector2i:
	match type:
		Type.WALL: return Vector2i(1, 1)
		Type.DEFENSE: return Vector2i(1, 1)
		Type.PRODUCTION: return Vector2i(2, 1)
		Type.COMMAND: return Vector2i(2, 2)
	return Vector2i(1, 1)

# 承伤 HP（对齐《波次系统 GDD》§5.3 HP 表）
static func hp(type: int) -> int:
	match type:
		Type.WALL: return 120
		Type.DEFENSE: return 300
		Type.PRODUCTION: return 200
		Type.COMMAND: return 600   # 对齐《波次系统 GDD》§5.3 指挥核心 HP
	return 100

# 美术表现：不用拉伸后的低清像素精灵，改用色块 + 符号，保证任意尺寸都清晰可读
static func color(type: int) -> Color:
	match type:
		Type.WALL: return Color(0.45, 0.42, 0.38)       # 石褐
		Type.DEFENSE: return Color(0.20, 0.58, 0.82)    # 炮塔蓝
		Type.PRODUCTION: return Color(0.22, 0.70, 0.38) # 生产绿
		Type.COMMAND: return Color(0.91, 0.57, 0.24)    # 暖橙核心（美术圣经威胁色）
	return Color(0.5, 0.5, 0.5)

static func symbol(type: int) -> String:
	match type:
		Type.WALL: return "墙"
		Type.DEFENSE: return "防"
		Type.PRODUCTION: return "产"
		Type.COMMAND: return "核"
	return "?"

# 保留旧接口，但 main.gd 优先使用 color/symbol 绘制
static func texture(type: int) -> Texture2D:
	match type:
		Type.WALL: return load("res://assets/art/tile_wall.png")
		Type.DEFENSE: return load("res://assets/art/room_defense.png")
		Type.PRODUCTION: return load("res://assets/art/room_production.png")
		Type.COMMAND: return load("res://assets/art/room_command.png")
	return load("res://assets/art/tile_wall.png")
