extends RefCounted

const RoomDefs := preload("res://core/room_defs.gd")

# 玩家放置/移动/升级/拆除指令（对齐《建造系统 GDD》§4 GridCommand）
enum Action { PLACE, MOVE, UPGRADE, DEMOLISH }

var action: int = Action.PLACE
var room_type: int = 0
var cells = []          # Array[Vector2i]
var rotation: int = 0

static func place(room_type: int, origin: Vector2i) -> GridCommand:
	var c = GridCommand.new()
	c.action = Action.PLACE
	c.room_type = room_type
	var s = RoomDefs.size(room_type)
	for dx in range(s.x):
		for dy in range(s.y):
			c.cells.append(origin + Vector2i(dx, dy))
	return c
