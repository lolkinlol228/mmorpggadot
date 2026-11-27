extends RefCounted
## Точки добычи, два поселения и пещера на существующей карте.

const MINE := Rect2(2600, 200, 900, 700)
# Перемычки оставляют по одному проходу между четырьмя выработками.
const MINE_WALLS := [Rect2(2850, 200, 18, 482), Rect2(2850, 758, 18, 142),
	Rect2(3020, 200, 18, 338), Rect2(3020, 614, 18, 286),
	Rect2(3270, 200, 18, 172), Rect2(3270, 448, 18, 452)]
const MINE_GATE := Vector2(1648, 1100)
const MINE_EXIT := Vector2(2650, 815)
const CAVE := Rect2(2030, 1440, 330, 130)
const CAMPS := {"ford": Vector2(1020, 1005), "east": Vector2(1585, 1080)}
const CAMP_NAMES := {"ford": "Пепельный Брод", "east": "Пристань"}
const SOURCES := [
	["ore", "Рудная жила", Vector2(1310, 775)], ["ore", "Глубокая жила", Vector2(2240, 1480), 2],
	["wood", "Древесина", Vector2(1830, 880)], ["wood", "Старая сосна", Vector2(2200, 800), 2],
	["cloth", "Лён", Vector2(845, 654)], ["cloth", "Шёлк", Vector2(1900, 700), 2],
	["fish", "Рыбалка", Vector2(1620, 1052)], ["fish", "Рыбалка", Vector2(900, 570), 2],
	["herb", "Лечебные травы", Vector2(1980, 930)],
	["chest", "Скрытый тайник", Vector2(2180, 1460)], ["chest", "Скрытый тайник", Vector2(1400, 660)],
	["workshop", "Мастерская Горна", Vector2(931, 976)],
	["cave", "Вход в пещеру", Vector2(2020, 1420)],
	["exit", "Выход из пещеры", Vector2(2070, 1460)],
	["camp", "Пристань", Vector2(1585, 1080)]
]
const HAZARDS := [
	["cold", Vector2(1135, 405)], ["fire", Vector2(2270, 1510)], ["poison", Vector2(2120, 1500)],
	["trap", Vector2(2330, 1500)]
]


## Находит точку вне препятствий карты.
static func mine_wall_between(a: Vector2, b: Vector2) -> bool:
	for wall: Rect2 in MINE_WALLS:
		var top_right := Vector2(wall.end.x, wall.position.y)
		var bottom_left := Vector2(wall.position.x, wall.end.y)
		if Geometry2D.segment_intersects_segment(a, b, wall.position, bottom_left) != null or Geometry2D.segment_intersects_segment(a, b, top_right, wall.end) != null:
			return true
		if Geometry2D.segment_intersects_segment(a, b, wall.position, top_right) != null or Geometry2D.segment_intersects_segment(a, b, bottom_left, wall.end) != null:
			return true
	return false


static func open_point(world, origin: Vector2) -> Vector2:
	if not world.blocked(origin, 9.0):
		return origin
	for radius in [12.0, 24.0, 36.0, 48.0]:
		for i in 12:
			var point: Vector2 = origin + Vector2.from_angle(TAU * i / 12.0) * radius
			if not world.blocked(point, 9.0):
				return point
	return origin


## Единые места взаимодействия для клиента и хоста.
static func spots(world) -> Array:
	var result := []
	for i in SOURCES.size():
		var row: Array = SOURCES[i]
		var pt := open_point(world, row[2])
		result.append({"kind": "adventure", "action": row[0], "label": row[1], "x": pt.x, "y": pt.y,
			"h": 7, "id": str(i), "tier": row[3] if row.size() > 3 else 1})
	return result


## Участки дороги и волчьего леса.
static func on_road(pos: Vector2) -> bool:
	return Rect2(985, 680, 70, 490).has_point(pos) or Rect2(800, 1024, 1450, 52).has_point(pos)


static func forest(pos: Vector2) -> bool:
	return Rect2(1720, 680, 620, 700).has_point(pos) and not on_road(pos)


static func water(pos: Vector2) -> bool:
	return Rect2(1410, 660, 165, 690).has_point(pos) and not on_road(pos)



## Стража защищает Брод и рыбацкую пристань.
static func is_safe(world, pos: Vector2, margin: float = 0.0) -> bool:
	return world.in_town(pos, margin) or pos.distance_to(CAMPS.east) <= 55.0
