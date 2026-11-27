extends Node
## Карта из tools/art/world.py: размеры, зоны, коллизии (прямоугольники и круги).
## Коллизии разложены по сетке 128 px, чтобы проверка была быстрой.

const LAYOUT := "res://assets/custom/world/layout.json"
const Sites := preload("res://scripts/adventure_sites.gd")
const Quest := preload("res://scripts/mine_quest.gd")
var mine_open := false
const CELL := 128.0

var size := Vector2(2400, 1600)
var spawn := Vector2(1020, 1005)
var town := Rect2()
var zones := {}
var props: Array = []
var night := 0.0     # 0 — день, 1 — ночь (ставит ambience.gd)
var _grid := {}      # Vector2i -> Array of [type, data]


func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not (data is Dictionary):
		push_error("layout.json не загрузился")
		return
	size = Vector2(data.size[0], data.size[1])
	zones = data.zones
	spawn = Vector2(zones.spawn[0], zones.spawn[1])
	var t: Array = zones.town
	town = Rect2(t[0], t[1], t[2] - t[0], t[3] - t[1])
	props = data.props
	var sites := preload("res://scripts/adventure_sites.gd")
	zones.interact.append({"kind": "market", "x": 1100, "y": 1010, "h": 22, "label": "Рынок"})
	zones.interact.append({"kind": "market", "x": sites.CAMPS.east.x + 30, "y": sites.CAMPS.east.y, "h": 22, "label": "Рынок"})
	for pair in [[sites.MINE_GATE, "Затопленная шахта", "enter"], [sites.MINE_EXIT, "К Пристани", "leave"]]:
		zones.interact.append({"kind": "mine", "x": pair[0].x, "y": pair[0].y, "label": pair[1], "action": pair[2], "h": 12})
	for spot in zones.interact:
		if spot.label in ["Рыбак", "Горн, кузнец"]:
			spot.actor = "fisher" if spot.label == "Рыбак" else "smith"
	for r in data.rects:
		_add(Rect2(r[0], r[1], r[2], r[3]), ["r", Rect2(r[0], r[1], r[2], r[3])])
	for c in data.circles:
		var rad: float = c[2]
		_add(Rect2(c[0] - rad, c[1] - rad, rad * 2, rad * 2), ["c", Vector3(c[0], c[1], rad)])


func update_mine(p: Dictionary) -> void:
	mine_open = p.mine_open
	for spot in zones.interact:
		if spot.has("actor"):
			spot.lines = [Quest.dialogue(spot.actor, mine_open, p)]


func _add(bounds: Rect2, entry: Array) -> void:
	for gx in range(int(bounds.position.x / CELL), int(bounds.end.x / CELL) + 1):
		for gy in range(int(bounds.position.y / CELL), int(bounds.end.y / CELL) + 1):
			var k := Vector2i(gx, gy)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(entry)


func add_circle(p: Vector2, r: float) -> void:
	_add(Rect2(p.x - r, p.y - r, r * 2, r * 2), ["c", Vector3(p.x, p.y, r)])


func blocked(p: Vector2, r: float) -> bool:
	if Sites.MINE.has_point(p):
		for wall: Rect2 in Sites.MINE_WALLS:
			if wall.grow(r).has_point(p):
				return true
		return not Sites.MINE.grow(-maxf(10.0, r)).has_point(p)
	if not mine_open and p.distance_to(Sites.MINE_GATE) < 13.0 + r:
		return true
	if p.x < 28 or p.y < 28 or p.x > size.x - 28 or p.y > size.y - 28:
		return true
	var k := Vector2i(int(p.x / CELL), int(p.y / CELL))
	for e in _grid.get(k, []):
		if e[0] == "r":
			var rc: Rect2 = e[1]
			var q := Vector2(clampf(p.x, rc.position.x, rc.end.x), clampf(p.y, rc.position.y, rc.end.y))
			if q.distance_squared_to(p) < r * r:
				return true
		else:
			var c: Vector3 = e[1]
			if Vector2(c.x, c.y).distance_squared_to(p) < (c.z + r) * (c.z + r):
				return true
	return false


## Двигает точку с учётом препятствий: по осям отдельно, чтобы скользить вдоль стен.
func move(p: Vector2, delta: Vector2, r := 5.0) -> Vector2:
	var out := p
	if not blocked(out + Vector2(delta.x, 0), r):
		out.x += delta.x
	if not blocked(out + Vector2(0, delta.y), r):
		out.y += delta.y
	return out


func in_town(p: Vector2, margin := 24.0) -> bool:
	return town.grow(margin).has_point(p)


## Случайная свободная точка в зоне врагов ("slime" — эллипс, "wolf" — прямоугольник, "golem" — центр).
func random_spawn(kind: String) -> Vector2:
	for i in 40:
		var p: Vector2
		match kind:
			"slime":
				var z: Array = zones.slime
				var a := randf() * TAU
				var d := sqrt(randf())
				p = Vector2(z[0] + cos(a) * z[2] * d, z[1] + sin(a) * z[3] * d)
			"wolf":
				var z: Array = zones.wolf
				p = Vector2(randf_range(z[0], z[2]), randf_range(z[1], z[3]))
			_:
				var z: Array = zones.golem
				p = Vector2(z[0], z[1]) + Vector2.from_angle(randf() * TAU) * randf() * 40.0
		if not blocked(p, 12.0):
			return p
	return Vector2(zones.golem[0], zones.golem[1])
