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

# ---------- баланс: потолки и защита врагов ----------
# Дары складываются между собой, с расой, классом и вещами. Чтобы сочетания не ломали игру,
# итоговые значения обрезаются этими потолками (доли: 0.6 = 60%; для cd — минимальный множитель).
const CAPS := {
	"crit": 0.60,          # шанс крита всего
	"dodge": 0.35,         # уклонение
	"cd_mult_min": 0.60,   # перезарядки короче максимум на 40%
	"lifesteal": 0.20,     # вампиризм
	"speed": 0.45,         # прибавка к скорости бега
	"aspd": 0.60,          # прибавка к скорости атаки
	"dmg": 1.00,           # прибавка к урону от всех даров вместе (+100%)
	"hp": 0.60,            # прибавка к здоровью от даров
	"loot": 1.00,          # шанс выпадения вещей ×2 максимум
	"rare_find": 0.50,     # сдвиг к редким вещам
	"coin": 1.00,          # монеты ×2 максимум
	"xp": 1.00,            # опыт ×2 максимум
	"thorns": 0.30,        # возврат урона
}
const PROC_ICD := 0.4          # сек: один и тот же дар не срабатывает по удару чаще
const DOT_MAX_STACKS := 10     # кровотечение / яд / огонь копятся не больше
# Боссы (голем, будущие боссы подземелий) и элита: что на них не действует или ослаблено.
const BOSS_RULES := {
	"immune": ["instakill", "execute", "knockback", "fear"],
	"cc_mult": 0.25,           # оглушение и замедление в 4 раза короче
	"dot_max_frac": 0.01,      # урон со временем — не больше 1% их здоровья в секунду
}

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


const COMBAT_KEYS := ["hp", "armor", "dmg", "crit", "aspd", "speed", "cd", "heal", "mana", "mana_regen", "stam_regen", "hp_regen"]

## Вклад одного активного дара.
static func contribution(gift: Dictionary, key: String) -> float:
	var mods: Dictionary = gift.get("mods", {})
	var all := float(mods.get("all", 0.0)) if key in COMBAT_KEYS else 0.0
	return float(mods.get(key, 0.0)) + (-all if key == "cd" else all)


## Сумма пассивных добавок, в том числе для будущих систем ремёсел.
static func mod(p: Dictionary, key: String) -> float:
	var total := 0.0
	for id in p.get("gifts", []):
		var gift := get_gift(id)
		if not gift.has("when"):
			total += contribution(gift, key)
	return total


## Есть ли у героя особая механика.
static func has_flag(p: Dictionary, flag: String) -> bool:
	for id in p.get("gifts", []):
		if get_gift(id).get("flag", "") == flag:
			return true
	return false


## Множитель с потолком положительной добавки.
static func factor(p: Dictionary, key: String) -> float:
	return maxf(0.0, 1.0 + minf(mod(p, key), float(CAPS.get(key, INF))))
