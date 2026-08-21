extends RefCounted
class_name GridModel

# 网格模型：最大 18x18，初始 6x6（Lv1），随等级扩展
# 纯逻辑层（无节点依赖），可后续搬到服务端 headless 结算（ADR-002）

var size: int = 6
var occupied = {}   # Vector2i -> room_id
var rooms = {}      # room_id -> {type, origin, cells, hp}
var next_id: int = 0

# 堡垒生长曲线（对齐《建造系统 GDD》§5.2）
func set_level(lv: int) -> void:
	var table = [6, 8, 10, 12, 14, 16, 18, 18, 18]
	size = table[min(lv, table.size() - 1)]

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size

func can_place(type: int, origin: Vector2i) -> bool:
	var s = RoomDefs.size(type)
	for dx in range(s.x):
		for dy in range(s.y):
			var c = origin + Vector2i(dx, dy)
			if not in_bounds(c):
				return false
			if occupied.has(c):
				return false
	return true

func place(type: int, origin: Vector2i) -> int:
	if not can_place(type, origin):
		return -1
	var s = RoomDefs.size(type)
	var cells = []
	for dx in range(s.x):
		for dy in range(s.y):
			cells.append(origin + Vector2i(dx, dy))
	var id = next_id
	next_id += 1
	rooms[id] = {"type": type, "origin": origin, "cells": cells, "hp": RoomDefs.hp(type)}
	for c in cells:
		occupied[c] = id
	return id

func demolish(id: int) -> void:
	if not rooms.has(id):
		return
	for c in rooms[id]["cells"]:
		occupied.erase(c)
	rooms.erase(id)
