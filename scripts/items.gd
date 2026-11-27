extends Node
## База предметов, редкости, враги и броски лута.
## Все шансы собраны здесь — крути их, чтобы настроить "радость от дропа".

const Gifts := preload("res://scripts/gifts.gd")

const MAX_INV := 24
const MAX_BANK := 48
# Доска заказов: убей N врагов вида kind — получи награду (в медяках). Можно брать снова.
const BOUNTIES := [
	{"id": "slime10", "title": "Очистить топь", "text": "Убей 10 слизней", "kind": "slime", "need": 10, "reward": 60},
	{"id": "wolf5", "title": "Волчья угроза", "text": "Убей 5 волков за мостом", "kind": "wolf", "need": 5, "reward": 160},
	{"id": "golem1", "title": "Пробуждённый камень", "text": "Победи Каменного Голема", "kind": "golem", "need": 1, "reward": 900},
]
# Что продаёт торговка (обычное качество) — по цене value()*3
const SHOP_STOCK := ["potion", "sword", "axe", "dagger", "hammer", "staff", "wand", "bow", "helm", "hood", "armor",
	"jerkin", "robe", "boots"]
const SLOTS := ["weapon", "head", "body", "feet", "offhand"]
const SLOT_NAMES := {"weapon": "Оружие", "head": "Голова", "body": "Тело", "feet": "Ноги", "offhand": "Щит", "use": "Расходник", "currency": "Монеты", "trophy": "Трофей"}

# "icon" — клетка в assets/icons/shikashi_icons.png (сетка 32×32).
const BASES := {
	"shield": {"name": "Щит", "slot": "offhand", "dmg": 0, "armor": 4, "icon": Vector2i(7, 7)},
	"meal": {"name": "Рыбное рагу", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(9, 12), "stack": 10},
	"scroll": {"name": "Свиток силы", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(2, 10), "stack": 10},
	"book": {"name": "Книга боя", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(3, 10), "stack": 10},
	"sword": {"name": "Меч", "slot": "weapon", "dmg": 5, "armor": 0, "icon": Vector2i(1, 5)},
	"axe": {"name": "Топор", "slot": "weapon", "dmg": 7, "armor": 0, "icon": Vector2i(11, 5)},
	"dagger": {"name": "Кинжал", "slot": "weapon", "dmg": 4, "armor": 0, "icon": Vector2i(6, 5)},
	"staff": {"name": "Посох", "slot": "weapon", "dmg": 6, "armor": 0, "icon": Vector2i(8, 6)},
	"wand": {"name": "Жезл", "slot": "weapon", "dmg": 4, "armor": 0, "icon": Vector2i(9, 6)},
	"bow": {"name": "Лук", "slot": "weapon", "dmg": 5, "armor": 0, "icon": Vector2i(3, 6)},
	"hammer": {"name": "Боевой молот", "slot": "weapon", "dmg": 6, "armor": 0, "icon": Vector2i(11, 5)},
	"helm": {"name": "Шлем", "slot": "head", "dmg": 0, "armor": 2, "kind": "plate", "icon": Vector2i(1, 7)},
	"hood": {"name": "Капюшон", "slot": "head", "dmg": 1, "armor": 1, "kind": "leather", "icon": Vector2i(2, 7)},
	"armor": {"name": "Кираса", "slot": "body", "dmg": 0, "armor": 4, "kind": "plate", "icon": Vector2i(5, 7)},
	"jerkin": {"name": "Кожаная куртка", "slot": "body", "dmg": 1, "armor": 3, "kind": "leather", "icon": Vector2i(6, 7)},
	"robe": {"name": "Мантия", "slot": "body", "dmg": 2, "armor": 2, "kind": "cloth", "icon": Vector2i(14, 7)},
	"boots": {"name": "Сапоги", "slot": "feet", "dmg": 0, "armor": 1, "icon": Vector2i(3, 8)},
	"abyss_blade": {"name": "Клинок Бездны", "slot": "weapon", "dmg": 30, "armor": 0, "unique": true, "icon": Vector2i(0, 3)},
	"dawn_crown": {"name": "Корона Рассвета", "slot": "head", "dmg": 5, "armor": 12, "unique": true, "icon": Vector2i(9, 3)},
	"potion": {"name": "Зелье лечения", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(0, 9), "stack": 10, "heal": 45},
	"coins": {"name": "Монеты", "slot": "currency", "dmg": 0, "armor": 0, "icon": Vector2i(10, 12)},
	# трофеи — падают с врагов; из них в мастерской делают компоненты (relics.gd)
	"slime_gel": {"name": "Сгусток слизи", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(2, 18), "stack": 99},
	"wolf_fang": {"name": "Клык вожака", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(9, 17), "stack": 99},
	"golem_shard": {"name": "Осколок ядра голема", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(2, 17), "stack": 99},
	"echo_dust": {"name": "Прах эха", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(2, 20), "stack": 99},
	"elite_mark": {"name": "Метка чемпиона", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(4, 18), "stack": 99},
	# компоненты — из трофеев; из компонентов — реликвии
	"acid_essence": {"name": "Кислотная эссенция", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(2, 9), "stack": 20, "component": true},
	"pack_charm": {"name": "Оберег стаи", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(8, 11), "stack": 20, "component": true},
	"golem_heart": {"name": "Сердце голема", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(15, 12), "stack": 20, "component": true},
	"lantern_soul": {"name": "Душа фонаря", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(9, 10), "stack": 20, "component": true},
	"champion_seal": {"name": "Печать чемпиона", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 20, "component": true},
	# рецепты реликвий — выбиваются или собираются из обрывков; клик в сумке — изучить навсегда (relics.gd)
	"recipe_scrap": {"name": "Обрывок рецепта", "slot": "trophy", "dmg": 0, "armor": 0, "icon": Vector2i(12, 13), "stack": 99},
	"recipe_acid_blade": {"name": "Рецепт: Разъедающий клинок", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 5, "teaches": "acid_blade"},
	"recipe_moon_bow": {"name": "Рецепт: Лук Лунной стаи", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 5, "teaches": "moon_bow"},
	"recipe_mountain_hammer": {"name": "Рецепт: Молот Каменной Горы", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 5, "teaches": "mountain_hammer"},
	"recipe_soul_lantern": {"name": "Рецепт: Фонарь душ", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 5, "teaches": "soul_lantern"},
	"recipe_shadow_fang": {"name": "Рецепт: Клык тени", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 5, "teaches": "shadow_fang"},
	"recipe_dawn_scepter": {"name": "Рецепт: Скипетр Рассвета", "slot": "use", "dmg": 0, "armor": 0, "icon": Vector2i(11, 13), "stack": 5, "teaches": "dawn_scepter"},
	# реликвии — именное оружие из компонентов; art — чей спрайт, grants — дары, которые оно даёт владельцу
	"acid_blade": {"name": "Разъедающий клинок", "slot": "weapon", "dmg": 20, "armor": 0, "art": "sword", "relic": true,
		"grants": ["poisoned_blade", "armor_breaker"], "glow": Color(0.5, 1.0, 0.35), "icon": Vector2i(1, 5)},
	"moon_bow": {"name": "Лук Лунной стаи", "slot": "weapon", "dmg": 18, "armor": 0, "art": "bow", "relic": true,
		"grants": ["frost_touch", "steady_aim"], "glow": Color(0.6, 0.8, 1.0), "icon": Vector2i(3, 6)},
	"mountain_hammer": {"name": "Молот Каменной Горы", "slot": "weapon", "dmg": 24, "armor": 0, "art": "hammer", "relic": true,
		"grants": ["knockback", "giant_slayer"], "glow": Color(1.0, 0.7, 0.35), "icon": Vector2i(11, 5)},
	"soul_lantern": {"name": "Фонарь душ", "slot": "weapon", "dmg": 19, "armor": 0, "art": "staff", "relic": true,
		"grants": ["mana_thief", "storm_caller"], "glow": Color(0.7, 0.55, 1.0), "icon": Vector2i(8, 6)},
	"shadow_fang": {"name": "Клык тени", "slot": "weapon", "dmg": 16, "armor": 0, "art": "dagger", "relic": true,
		"grants": ["first_strike", "bleeder"], "glow": Color(0.45, 0.9, 0.5), "icon": Vector2i(6, 5)},
	"dawn_scepter": {"name": "Скипетр Рассвета", "slot": "weapon", "dmg": 15, "armor": 0, "art": "wand", "relic": true,
		"grants": ["gentle_hands", "healing_aura"], "glow": Color(1.0, 0.9, 0.5), "icon": Vector2i(9, 6)},
}

# ---- деньги: всё хранится в медяках, показывается номиналами ----
const COIN_VALUES := [2000, 200, 20, 1]                       # платина, золото, серебро, медь
const COIN_NAMES := ["Платиновый Осколок", "Золотой", "Серебряник", "Медяк"]
const COIN_SHORT := ["пл.", "зол.", "сер.", "мед."]
const COIN_SHEET := preload("res://assets/custom/coins.png")     # медь, серебро, золото, платина
# цена предметов в медяках (до множителя редкости)
const VALUE := {"recipe_scrap": 25, "recipe_acid_blade": 700, "recipe_moon_bow": 900, "recipe_mountain_hammer": 1500,
	"recipe_soul_lantern": 1100, "recipe_shadow_fang": 1100, "recipe_dawn_scepter": 1200,
	"slime_gel": 2, "wolf_fang": 6, "golem_shard": 40, "echo_dust": 5, "elite_mark": 30,
	"acid_essence": 60, "pack_charm": 120, "golem_heart": 300, "lantern_soul": 150, "champion_seal": 260,
	"acid_blade": 2500, "moon_bow": 3000, "mountain_hammer": 4500, "soul_lantern": 3500, "shadow_fang": 3500, "dawn_scepter": 3800,
	"shield": 14, "meal": 4, "scroll": 7, "book": 9,"sword": 12, "axe": 15, "dagger": 9, "staff": 14, "wand": 11, "bow": 13, "hammer": 15, "jerkin": 14,
	"helm": 10, "hood": 6, "armor": 18, "robe": 12,
	"boots": 6, "potion": 8, "abyss_blade": 6000, "dawn_crown": 6000}
const RARITY_VALUE := [1, 3, 10, 40, 220, 1500]
const COIN_DROPS := {"shell": [12, 22], "ringer": [8, 15], "warden": [600, 950], "slime": [2, 7], "wolf": [8, 34], "golem": [450, 900], "undead": [12, 30]}
const ICON_SHEET := preload("res://assets/icons/shikashi_icons.png")
# Своё оружие (tools/art/gen_art.py): строки — тип, столбцы — редкость 0..5.
const WEAPON_SHEET := preload("res://assets/custom/weapons.png")
const WEAPON_ROWS := ["sword", "axe", "dagger", "abyss_blade", "staff", "wand", "bow", "hammer"]
const UI_ICONS := {"gold": Vector2i(10, 12), "bag": Vector2i(0, 10), "trade": Vector2i(13, 12)}
const SLOT_ICONS := {"weapon": Vector2i(1, 5), "head": Vector2i(1, 7), "body": Vector2i(5, 7), "feet": Vector2i(3, 8), "offhand": Vector2i(7, 7)}
var _icon_cache := {}
const COMMON_BASES := ["sword", "axe", "dagger", "staff", "wand", "bow", "hammer", "helm", "hood", "armor", "jerkin",
	"robe", "boots"]
# Как бьёт оружие: ближние стили — взмах, дальние (bolt, shot) — снаряд по прямой.
const WEAPON_STYLE := {"sword": "slash", "abyss_blade": "slash", "axe": "chop", "hammer": "chop", "dagger": "stab",
	"staff": "bolt", "wand": "bolt", "bow": "shot"}
const KIND_NAMES := {"plate": "латы", "leather": "кожа", "cloth": "ткань"}
const UNIQUE_BASES := ["abyss_blade", "dawn_crown"]

const RARITY_NAMES := ["Обычный", "Необычный", "Редкий", "Эпический", "Легендарный", "Мифический"]
const RARITY_COLORS := [
	Color(0.82, 0.82, 0.82), Color(0.35, 0.9, 0.35), Color(0.3, 0.6, 1.0),
	Color(0.75, 0.4, 1.0), Color(1.0, 0.6, 0.1), Color(1.0, 0.22, 0.38),
]
const RARITY_MULT := [1.0, 1.35, 1.8, 2.5, 3.5, 5.0]
const SHINY_COLOR := Color(1.0, 0.88, 0.3)

# Веса редкостей на 100 000 бросков.
const MOB_WEIGHTS := [70000, 22000, 6500, 1300, 180, 20]   # мифик ≈ 1 из 5000 дропов
const BOSS_WEIGHTS := [0, 35000, 40000, 20000, 4500, 500]  # мифик ≈ 1 из 200 дропов
const MOB_DROP_CHANCE := 0.45
const BOSS_DROPS := 4
const SHINY_CHANCE := 0.001          # "сияющая" версия любого предмета: 1 из 1000
const BOSS_UNIQUE_CHANCE := 0.0025   # уникальный предмет босса: ~1% за убийство голема

const ENEMIES := {
	"shell": {"name": "Панцирник", "hp": 85, "dmg": 15, "speed": 53.0, "radius": 16.0,
		"aggro": 142.0, "cooldown": 2.4, "color": Color.SLATE_GRAY},
	"ringer": {"name": "Звонарь", "hp": 48, "dmg": 5, "speed": 61.0, "radius": 12.0,
		"aggro": 146.0, "cooldown": 2.5, "color": Color.GOLDENROD},
	"warden": {"name": "Колокольный Страж", "hp": 1600, "dmg": 23, "speed": 53.0, "radius": 30.0,
		"aggro": 190.0, "cooldown": 2.8, "color": Color.DARK_GOLDENROD},
	"undead": {"name": "Пещерный мертвец", "hp": 58, "dmg": 10, "speed": 75.0, "radius": 15.0,
		"aggro": 180.0, "cooldown": 1.6, "color": Color(0.5, 0.75, 0.55)},
	"slime": {"name": "Слизень", "hp": 24, "dmg": 4, "speed": 70.0, "radius": 14.0,
		"aggro": 260.0, "cooldown": 1.0, "color": Color(0.3, 0.62, 0.55)},
	"wolf": {"name": "Волк", "hp": 40, "dmg": 7, "speed": 115.0, "radius": 15.0,
		"aggro": 320.0, "cooldown": 0.9, "color": Color(0.55, 0.55, 0.62)},
	"golem": {"name": "Каменный Голем", "hp": 900, "dmg": 18, "speed": 55.0, "radius": 34.0,
		"aggro": 420.0, "cooldown": 1.4, "color": Color(0.55, 0.43, 0.32)},
}


## Разложить сумму в медяках на номиналы: [платина, золото, серебро, медь].
func split_coins(total: int) -> Array:
	var out := []
	var rest := maxi(0, total)
	for v in COIN_VALUES:
		out.append(rest / v)
		rest = rest % v
	return out


func format_coins(total: int) -> String:
	var parts := PackedStringArray()
	var s := split_coins(total)
	for i in 4:
		if s[i] > 0:
			parts.append("%d %s" % [s[i], COIN_SHORT[i]])
	return " ".join(parts) if parts.size() > 0 else "0 мед."


## Иконка монеты по номиналу (0 платина .. 3 медь).
func coin_icon(denom: int) -> AtlasTexture:
	var key := "coin%d" % denom
	if not _icon_cache.has(key):
		var t := AtlasTexture.new()
		t.atlas = COIN_SHEET
		t.region = Rect2([3, 2, 1, 0][denom] * 32, 0, 32, 32)
		_icon_cache[key] = t
	return _icon_cache[key]


func make_coins(amount: int) -> Dictionary:
	var it := make("coins", 0, "", false)
	it.count = maxi(1, amount)
	return it


func make_potion(count := 1) -> Dictionary:
	var it := make("potion", 0, "", false)
	it.count = count
	return it


func is_stack(it: Dictionary) -> bool:
	return BASES[it.base].has("stack")


## Цена в медяках (столько платит торговка; купить у неё — втрое дороже).
func value(it: Dictionary) -> int:
	if it.base == "coins":
		return int(it.get("count", 0))
	var v: int = VALUE.get(it.base, 5) * RARITY_VALUE[int(it.rarity)] * (5 if it.shiny else 1)
	return v * int(it.get("count", 1)) * (3 if it.get("golden", false) else 1)


## Иконка 32×32 из листа Shikashi по координатам клетки.
func icon_at(cell: Vector2i) -> AtlasTexture:
	if not _icon_cache.has(cell):
		var t := AtlasTexture.new()
		t.atlas = ICON_SHEET
		t.region = Rect2(cell.x * 32, cell.y * 32, 32, 32)
		_icon_cache[cell] = t
	return _icon_cache[cell]


func icon(it: Dictionary) -> AtlasTexture:
	if it.base == "coins":
		var s := split_coins(int(it.get("count", 1)))
		for i in 4:
			if s[i] > 0:
				return coin_icon(i)
		return coin_icon(3)
	var row := WEAPON_ROWS.find(art_base(it.base))
	if row >= 0:
		var key := "w%d_%d" % [row, int(it.rarity)]
		if not _icon_cache.has(key):
			var t := AtlasTexture.new()
			t.atlas = WEAPON_SHEET
			t.region = Rect2(int(it.rarity) * 32, row * 32, 32, 32)
			_icon_cache[key] = t
		return _icon_cache[key]
	return icon_at(BASES[it.base].icon)


func new_uid() -> String:
	return "%d-%d" % [Time.get_ticks_usec(), randi()]


func roll_rarity(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	var r := randi() % total
	for i in weights.size():
		if r < int(weights[i]):
			return i
		r -= int(weights[i])
	return 0


func roll_drop(boss: bool, mods: Dictionary = {}, rarity_shift: int = 0) -> Dictionary:
	var shiny := randf() < SHINY_CHANCE
	if boss and randf() < BOSS_UNIQUE_CHANCE:
		return make(UNIQUE_BASES.pick_random(), 5, "", shiny)
	var weights: Array = (BOSS_WEIGHTS if boss else MOB_WEIGHTS).duplicate()
	for i in weights.size():
		var bonus := float(mods.get("rare_find", 0.0)) if i >= 2 else 0.0
		var weight := float(weights[i]) * maxf(0.0, 1.0 + bonus)
		if i >= 4:
			weight *= 1.0 + float(mods.get("mega_rare", 0.0))
		if i == 5:
			weight *= 1.0 + float(mods.get("mythic_find", 0.0))
		weights[i] = roundi(weight * 100.0)
	var rarity := clampi(roll_rarity(weights) + rarity_shift, 0, 5)
	return make(COMMON_BASES.pick_random(), rarity, "", shiny)


func make(base: String, rarity: int, finder: String, shiny: bool) -> Dictionary:
	var b: Dictionary = BASES[base]
	var mult: float = RARITY_MULT[rarity] * (1.5 if shiny else 1.0) * randf_range(0.9, 1.15)
	return {
		"uid": new_uid(), "base": base, "rarity": rarity, "shiny": shiny,
		"dmg": int(round(b.dmg * mult)), "armor": int(round(b.armor * mult)),
		"finder": finder, "found": Time.get_date_string_from_system(), "serial": 0, "count": 1,
	}


## Приводит предмет из сети/файла к правильным типам. Пустой словарь = мусор.
func normalize(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var base := str(d.get("base", ""))
	if not BASES.has(base):
		return {}
	return {
		"uid": str(d.get("uid", new_uid())).left(40), "base": base,
		"rarity": clampi(int(d.get("rarity", 0)), 0, 5), "shiny": bool(d.get("shiny", false)), "golden": bool(d.get("golden", false)), "socketed": bool(d.get("socketed", false)),
		"dmg": clampi(int(d.get("dmg", 0)), 0, 999), "armor": clampi(int(d.get("armor", 0)), 0, 999),
		"finder": str(d.get("finder", "")).left(20), "found": str(d.get("found", "")).left(12),
		"serial": maxi(0, int(d.get("serial", 0))),
		"count": clampi(int(d.get("count", 1)), 1, 99999999),
	}


func slot_of(it: Dictionary) -> String:
	return BASES[it.base].slot


func is_jackpot(it: Dictionary) -> bool:
	return int(it.rarity) >= 4 or bool(it.shiny) or bool(it.get("golden", false))


func color(it) -> Color:
	if not (it is Dictionary) or it.is_empty():
		return RARITY_COLORS[0]
	if BASES.has(it.get("base", "")) and BASES[it.base].has("glow"):
		return BASES[it.base].glow                      # у каждой реликвии свой цвет
	return SHINY_COLOR if it.shiny or it.get("golden", false) else RARITY_COLORS[int(it.rarity)]


func display_name(it: Dictionary) -> String:
	if it.base == "coins":
		return format_coins(int(it.get("count", 1)))
	var n: String = BASES[it.base].name
	if is_stack(it) and int(it.get("count", 1)) > 1:
		n += " ×%d" % int(it.count)
	if it.get("golden", false):
		n = "Золотой трофей: " + n
	if it.shiny:
		n = "★ " + n
	if int(it.serial) > 0:
		n += " #%d" % int(it.serial)
	return n


func tooltip(it: Dictionary) -> String:
	var b: Dictionary = BASES[it.base]
	var lines := PackedStringArray([display_name(it)])
	if it.base == "potion":
		lines.append("Расходник · лечит %d здоровья" % b.heal)
		lines.append("Клик в сумке — выпить")
		lines.append("Цена у торговки: %s" % format_coins(value(it)))
		return "\n".join(lines)
	if b.has("teaches"):
		lines.append("Рецепт реликвии · клик в сумке — изучить навсегда")
		lines.append("Учит ковать: %s" % BASES[b.teaches].name)
		lines.append("Пока не прочитан, его можно продать или обменять")
		lines.append("Цена у торговки: %s" % format_coins(value(it)))
		return "\n".join(lines)
	if b.slot == "trophy":
		lines.append(("Компонент реликвии" if b.get("component", false) else "Трофей") + " · мастерская Горна")
		lines.append("Нужен для: " + preload("res://scripts/relics.gd").used_in(it.base))
		lines.append("Цена у торговки: %s" % format_coins(value(it)))
		return "\n".join(lines)
	if b.get("relic", false):
		lines.append("Реликвия · %s" % BASES[art_base(it.base)].name)
		var gifts := PackedStringArray()
		for g in b.grants:
			gifts.append(str(preload("res://scripts/gifts.gd").get_gift(g).get("name", g)))
		lines.append("★ Дары реликвии: " + ", ".join(gifts))
	lines.append("%s · %s%s" % [RARITY_NAMES[int(it.rarity)], SLOT_NAMES[b.slot],
		(" · " + KIND_NAMES[b.kind]) if b.has("kind") else ""])
	var who: String = Rules.classes_for(it.base)
	if who != "":
		lines.append("Для класса: " + who)
	if it.shiny:
		lines.append("★ Сияющий вариант (шанс 1 из 1000)")
	if it.get("golden", false):
		lines.append("Золотой трофей: цена продажи ×3")
	if b.get("unique", false):
		lines.append("Уникальный трофей Каменного Голема")
	if int(it.dmg) > 0:
		lines.append("Урон +%d" % int(it.dmg))
	if int(it.armor) > 0:
		lines.append("Броня +%d" % int(it.armor))
	if str(it.finder) != "":
		lines.append("Найден: %s, %s" % [it.finder, it.found])
	if int(it.serial) > 0:
		lines.append("Серийный № %d в этом мире" % int(it.serial))
	lines.append("Цена у торговки: %s" % format_coins(value(it)))
	return "\n".join(lines)


## Чей спрайт и стиль удара у предмета: реликвия выглядит и бьёт как своё базовое оружие.
func art_base(base: String) -> String:
	return str(BASES.get(base, {}).get("art", base))


func is_relic(it) -> bool:
	return it is Dictionary and not it.is_empty() and bool(BASES.get(it.base, {}).get("relic", false))


func style_of(it) -> String:
	if it is Dictionary and not it.is_empty():
		return WEAPON_STYLE.get(art_base(it.base), "slash")
	return "slash"


func kind_of(it: Dictionary) -> String:
	return str(BASES[it.base].get("kind", ""))


func total_dmg(equip: Dictionary) -> int:
	var s := 0
	for it in equip.values():
		if it is Dictionary:
			s += int(it.dmg)
	return s


func total_armor(equip: Dictionary) -> int:
	var s := 0
	for it in equip.values():
		if it is Dictionary:
			s += int(it.armor)
	return s


## Вместимость сумки и хранилища с учётом даров.
func bag_capacity(p: Dictionary) -> int:
	return MAX_INV + int(Gifts.mod(p, "bag"))


func bank_capacity(p: Dictionary) -> int:
	return MAX_BANK + int(Gifts.mod(p, "bank"))


## Цена сделки для героя. Лавка продаёт по тройной базовой цене.
func shop_price(p: Dictionary, it: Dictionary, buying: bool) -> int:
	var adjusted := value(it) * (3.0 if buying else 1.0) * Gifts.factor(p, "buy_price" if buying else "sell_price")
	return maxi(1, roundi(adjusted))
