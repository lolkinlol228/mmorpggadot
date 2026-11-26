extends RefCounted
## Дары судьбы: каталог из data/gifts.json и бросок при создании героя.
## Здесь только данные и бросок. Эффекты даров считает хост (host_gifts.gd).
## Использование: const Gifts := preload("res://scripts/gifts.gd"); Gifts.get_gift("berserk")

const PATH := "res://data/gifts.json"
const RARITIES := ["c", "r", "e", "l", "m"]
const RARITY_NAMES := {"c": "Обычный", "r": "Редкий", "e": "Эпический", "l": "Легендарный", "m": "Мифический"}
const RARITY_COLORS := {"c": Color(0.78, 0.76, 0.72), "r": Color(0.37, 0.66, 0.94), "e": Color(0.71, 0.49, 0.94),
	"l": Color(0.94, 0.63, 0.25), "m": Color(1.0, 0.37, 0.48)}
const WEIGHTS := {"c": 55.0, "r": 27.0, "e": 12.0, "l": 5.0, "m": 1.0}   # шанс редкости, %
const SECOND_CHANCE := 0.15          # шанс второго дара
const THIRD_CHANCE := 0.02           # шанс третьего (из всех бросков)
const REROLLS := 3                   # перебросов в создании героя
const MAX_GIFTS := 5                 # с пробуждениями на 25 и 50 уровнях

static var _all: Array = []
static var _by_id := {}


static func _load() -> void:
	if not _all.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Array:
		_all = parsed
		for g in _all:
			_by_id[str(g.id)] = g


static func all() -> Array:
	_load()
	return _all


static func get_gift(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})


static func exists(id: String) -> bool:
	_load()
	return _by_id.has(id)


static func color(id: String) -> Color:
	return RARITY_COLORS.get(str(get_gift(id).get("rarity", "c")), Color.WHITE)


## Сначала бросается редкость по WEIGHTS, потом дар внутри неё (без повторов из exclude).
static func roll_one(exclude: Array = []) -> String:
	_load()
	var x := randf() * 100.0
	var rar := "c"
	for r in RARITIES:
		if x < WEIGHTS[r]:
			rar = r
			break
		x -= WEIGHTS[r]
	var pool: Array = []
	for g in _all:
		if str(g.rarity) == rar and not exclude.has(str(g.id)):
			pool.append(str(g.id))
	return pool.pick_random() if not pool.is_empty() else ""


## Судьба нового героя: 1 дар, с шансом 15% — второй, 2% — третий.
static func roll_fate() -> Array:
	var out: Array = [roll_one()]
	if randf() < SECOND_CHANCE:
		out.append(roll_one(out))
		if randf() < THIRD_CHANCE / SECOND_CHANCE:
			out.append(roll_one(out))
	return out


## Проверка списка даров из сети или файла.
static func sanitize(list) -> Array:
	var out: Array = []
	if list is Array:
		for id in list:
			if exists(str(id)) and not out.has(str(id)) and out.size() < MAX_GIFTS:
				out.append(str(id))
	return out


static func tooltip(id: String) -> String:
	var g := get_gift(id)
	if g.is_empty():
		return ""
	return "%s — %s\n%s" % [g.name, RARITY_NAMES.get(str(g.rarity), ""), g.desc]
