extends RefCounted
## Добыча, инструменты, ремёсла и расходники. Все сделки выполняет хост.

const Gifts := preload("res://scripts/gifts.gd")
const Sites := preload("res://scripts/adventure_sites.gd")
const NAMES := {"ore": "Руда", "wood": "Древесина", "cloth": "Волокно", "hide": "Шкура", "fish": "Рыба", "herb": "Травы",
	"rich_ore": "Богатая руда", "rich_wood": "Крепкая древесина", "rich_cloth": "Тонкий шёлк", "rich_hide": "Крепкая шкура",
	"rich_fish": "Крупная рыба", "rich_herb": "Редкие травы", "gem": "Самоцвет", "ancient_wood": "Древняя древесина",
	"moon_silk": "Лунный шёлк", "prime_hide": "Отборная шкура", "star_iron": "Звёздное железо"}
const RECIPES := {
	"sword": ["smith", "ore", 3], "shield": ["smith", "ore", 3], "robe": ["tailor", "cloth", 3],
	"jerkin": ["tanner", "hide", 3], "staff": ["carpenter", "wood", 3], "meal": ["cook", "fish", 2],
	"scroll": ["scribe", "herb", 2], "book": ["scribe", "cloth", 3]
}
const PROFESSIONS := {"mining": "Горное дело", "smith": "Кузнечное дело", "tailor": "Ткачество",
	"tanner": "Кожевничество", "carpenter": "Плотницкое дело", "cook": "Кулинария", "scribe": "Письмо"}
const MAX_WEAR := 10.0
const BASE_CARRY := 30
const RESPAWN_MS := 25000

var host
var spots: Array = []
var ready_at := {}
var carcasses := {}


## Готовит общие для мира точки ресурсов.
func setup() -> void:
	spots = Sites.spots(World)


## Валидирует команду, владельца и расстояние перед выполнением действия.
func handle(pid: int, op: String, arg: String) -> void:
	var p: Dictionary = host.players[pid]
	var message := ""
	if op == "spot" and arg.is_valid_int():
		var i := int(arg)
		if i >= 0 and i < spots.size() and near(p, spots[i]):
			message = use_spot(pid, spots[i])
	elif op == "field":
		message = field(pid)
	elif op in ["make", "repair", "salvage", "transmute", "relic"] and near_workshop(p):
		match op:
			"relic": message = preload("res://scripts/relics.gd").craft(host, pid, arg)
			"make": message = craft(pid, arg)
			"repair":
				if p.coins >= 12 and float(p.tools.wear) > 0.0:
					p.coins -= 12
					p.tools.wear = 0.0
					message = "Инструменты восстановлены."
			"salvage": message = salvage(pid, arg)
			"transmute": message = transmute(pid, arg)
	if message != "":
		host._to(pid, "c_announce", [message, Color(0.95, 0.82, 0.54)])
		host._send_self(pid)


## Проверяет, что точка доступна игроку.
func near(p: Dictionary, spot: Dictionary) -> bool:
	return p.pos.distance_to(Vector2(spot.x, spot.y)) <= 64.0


## Проверяет расстояние до мастерской.
func near_workshop(p: Dictionary) -> bool:
	for spot in spots:
		if spot.action == "workshop":
			return near(p, spot)
	return false


## Направляет запрос к добыче, тайнику или переходу.
func use_spot(pid: int, spot: Dictionary) -> String:
	var p: Dictionary = host.players[pid]
	match str(spot.action):
		"chest":
			if int(ready_at.get(spot.id, 0)) > host.gifts.now():
				return "Тайник пуст."
			ready_at[spot.id] = host.gifts.now() + 90000
			var reward := roundi(45 * host.gifts.factor(pid, "chest_coin"))
			p.coins += reward
			return "В тайнике: %s" % Items.format_coins(reward)
		"cave":
			host.talents.travel(pid, Sites.CAVE.position + Vector2(85, 20))
			p.gift_dungeon_revived = false
			return "Вы вошли в Пещеру эха."
		"exit":
			host.talents.travel(pid, Vector2(2010, 1400))
			return "Вы вышли из пещеры."
		"camp":
			p.visited.east = true
			return "Поселение открыто: Пристань."
		"herb":
			if not host.gifts.has(p, "herbs"):
				return "Для сбора этих трав нужен дар травника."
	if spot.action == "workshop":
		return ""
	return start_gather(pid, str(spot.action), str(spot.id), int(spot.tier), Vector2(spot.x, spot.y))


## Разделывает ближайшую тушу, оставленную волком.
func field(pid: int) -> String:
	var p: Dictionary = host.players[pid]
	for id in carcasses.keys():
		var corpse: Dictionary = carcasses[id]
		if corpse.pos.distance_to(p.pos) <= 64.0:
			return start_gather(pid, "hide", id, int(corpse.tier), corpse.pos)
	return ""


## Создаёт временную точку разделки и показывает её игрокам.
func add_carcass(eid: int, e: Dictionary) -> void:
	var id := "hide_%d" % eid
	carcasses[id] = {"pos": e.pos, "tier": 2 if e.get("elite", false) else 1, "until": host.gifts.now() + 35000}
	host._all("c_adventure_mark", [id, e.pos, true])


## Удаляет исчезнувшие туши и завершает принятые операции.
func update() -> void:
	var now: int = host.gifts.now()
	for id in carcasses.keys():
		if now >= int(carcasses[id].until):
			remove_carcass(id)
	for pid in host.players.keys():
		var p: Dictionary = host.players[pid]
		var job: Dictionary = p.get("work", {})
		if job.is_empty():
			continue
		if p.hp <= 0 or p.pos.distance_to(job.pos) > 45.0 or int(p.get("hurt_at", 0)) > int(job.started):
			p.erase("work")
			host._to(pid, "c_announce", ["Работа прервана.", Color.ORANGE])
		elif now >= int(job.done):
			p.erase("work")
			var message := finish_craft(pid, job.key, job.material) if job.kind == "craft" else finish_gather(pid, job)
			host._to(pid, "c_announce", [message, Color.WHEAT])
			host._send_self(pid)


func remove_carcass(id: String) -> void:
	carcasses.erase(id)
	host._all("c_adventure_mark", [id, Vector2.ZERO, false])


## Резервирует время работы без списания инструментов и материалов.
func begin(pid: int, job: Dictionary, duration: float) -> void:
	var p: Dictionary = host.players[pid]
	job.started = host.gifts.now()
	job.done = int(job.started) + roundi(duration * 1000.0)
	job.pos = p.pos
	p.work = job


## Проверяет инструмент и доступность источника перед сбором.
func start_gather(pid: int, kind: String, id: String, tier: int, pos: Vector2) -> String:
	var p: Dictionary = host.players[pid]
	if p.has("work") or p.has("rescue"):
		return "Сначала завершите текущую работу."
	if host.gifts.now() < int(ready_at.get(id, 0)):
		return "Источник пока истощён."
	var reinforced: bool = host.gifts.has(p, "tool_tier_up")
	if float(p.tools.wear) >= MAX_WEAR and not reinforced:
		return "Инструмент изношен. Почините его в мастерской."
	var tool_tier := int(p.tools.tier) + int(reinforced)
	if tool_tier < tier:
		return "Нужен инструмент тира %d. Улучшение доступно в мастерской." % tier
	var speed: float = host.gifts.factor(pid, "gather_" + kind) * (1.0 + maxi(0, tool_tier - tier) * 0.15)
	begin(pid, {"kind": kind, "id": id, "tier": tier, "source_pos": pos}, 2.2 / maxf(0.1, speed))
	return "Начата добыча: %s." % NAMES[kind]


## Начисляет ресурсы и применяет срабатывания добычи до расхода источника.
func finish_gather(pid: int, job: Dictionary) -> String:
	var p: Dictionary = host.players[pid]
	if host.gifts.now() < int(ready_at.get(job.id, 0)) or (job.kind == "hide" and not carcasses.has(job.id)):
		return "Источник уже использован."
	var context := {"resource": job.kind, "amount": 1, "bonus": {}, "deplete": true}
	host.gifts.fire(pid, "gather", context)
	host.gifts.fire(pid, "gather_" + str(job.kind), context)
	var item := str(job.kind) if int(job.tier) == 1 else "rich_" + str(job.kind)
	if job.kind == "herb" and randf() < 0.15:
		item = "rich_herb"
	var additions: Dictionary = context.bonus.duplicate()
	additions[item] = int(additions.get(item, 0)) + int(context.amount)
	if job.kind == "ore" and randf() < 0.05 * proficiency(p, "mining"):
		additions[item] += 1
	if not add_materials(pid, additions):
		return "Ресурсы слишком тяжёлые. Освободите место в мастерской."
	if context.deplete:
		if job.kind == "hide":
			remove_carcass(job.id)
		else:
			ready_at[job.id] = host.gifts.now() + RESPAWN_MS
	if not host.gifts.has(p, "tool_tier_up"):
		p.tools.wear = minf(MAX_WEAR, float(p.tools.wear) + host.gifts.factor(pid, "tool_wear"))
	if job.kind == "ore":
		gain_xp(pid, "mining", 10)
	var gained := PackedStringArray()
	for key in additions:
		gained.append("%s ×%d" % [NAMES[key], additions[key]])
	return "Добыто: " + ", ".join(gained)


## Прибавляет материалы вместе, только если помещается вся добыча.
func add_materials(pid: int, additions: Dictionary) -> bool:
	var p: Dictionary = host.players[pid]
	var weight := 0
	for amount in p.materials.values():
		weight += int(amount)
	for amount in additions.values():
		weight += int(amount)
	if weight > floori(BASE_CARRY * host.gifts.factor(pid, "carry")):
		return false
	for key in additions:
		p.materials[key] = int(p.materials.get(key, 0)) + int(additions[key])
	return true


## Проверяет рецепт и оставляет материалы в сумке до конца работы.
func craft(pid: int, requested: String) -> String:
	var p: Dictionary = host.players[pid]
	if p.has("work") or p.has("rescue"):
		return "Сначала завершите текущую работу."
	if requested == "tool":
		if int(p.tools.tier) >= 2 or p.coins < 40 or int(p.materials.get("ore", 0)) < 4:
			return "Для улучшения нужны инструмент первого тира, 40 медяков и 4 руды."
		begin(pid, {"kind": "craft", "key": "tool", "material": "ore"}, 3.0 / maxf(0.1, host.gifts.factor(pid, "craft_speed")))
		return "Улучшение инструмента начато."
	if requested.begins_with("gem:"):
		return infuse(pid, requested.trim_prefix("gem:"))
	var key := requested.trim_suffix(":fine")
	var recipe: Array = RECIPES.get(key, [])
	if recipe.is_empty():
		return ""
	var material := str(recipe[1])
	if requested.ends_with(":fine"):
		if key in ["meal", "scroll", "book"]:
			return "Этот рецепт использует обычные материалы."
		material = str({"ore": "star_iron", "wood": "ancient_wood", "cloth": "moon_silk", "hide": "prime_hide"}[material])
		if int(p.materials.get(material, 0)) < int(recipe[2]):
			material = "rich_" + str(recipe[1])
	if int(p.materials.get(material, 0)) < int(recipe[2]):
		return "Не хватает: %s ×%d." % [NAMES[material], recipe[2]]
	begin(pid, {"kind": "craft", "key": key, "material": material}, 3.0 / maxf(0.1, host.gifts.factor(pid, "craft_speed")))
	return "Изготовление: %s." % Items.BASES[key].name


## Завершает ремесло и выдаёт предмет с учётом редкости и дара.
func finish_craft(pid: int, key: String, material: String) -> String:
	var p: Dictionary = host.players[pid]
	var context := {"free": false}
	host.gifts.fire(pid, "craft", context)
	if key == "tool":
		if p.coins < 40 or int(p.materials.get("ore", 0)) < 4:
			return "Условия улучшения изменились."
		if not context.free:
			p.materials.ore -= 4
		p.tools = {"wear": 0.0, "tier": 2}
		p.coins -= 40
		return "Инструмент улучшен."
	var recipe: Array = RECIPES[key]
	var count := int(recipe[2])
	if int(p.materials.get(material, 0)) < count:
		return "Материалы уже использованы."
	var fail: bool = not host.gifts.has(p, "no_fail") and randf() < 0.10
	if not fail:
		var boosted := 0.12 + float(host.gifts.mod(pid, "craft_rare")) + 0.05 * proficiency(p, str(recipe[0]))
		var rarity := int(material != recipe[1]) + int(randf() < boosted)
		rarity += int(host.gifts.has(p, "craft_rarity_up"))
		if host.gifts.has(p, "craft_mythic") and randf() < 0.02:
			rarity = 5
		var item := Items.make(key, rarity, p.name, false)
		if host.gifts.has(p, "craft_extra_affix") and key not in ["meal", "scroll", "book"]:
			var affix := "dmg" if randf() < 0.5 else "armor"
			item[affix] += 1
		if not host.eco.add_item(p, item):
			return "Сумка полна."
	if not context.free:
		p.materials[material] -= count
	gain_xp(pid, str(recipe[0]), 5 if fail else 15)
	return "Изготовление не удалось." if fail else "Готово: %s." % Items.BASES[key].name


## Разбирает экипировку в ресурс без потери предмета при переполнении.
func salvage(pid: int, uid: String) -> String:
	var p: Dictionary = host.players[pid]
	var index: int = host._find(p.inv, uid)
	if index < 0:
		return "Выберите предмет из сумки."
	var item: Dictionary = p.inv[index]
	var base: Dictionary = Items.BASES[item.base]
	if base.slot not in Items.SLOTS:
		return "Этот предмет нельзя разобрать."
	var key := str({"cloth": "cloth", "leather": "hide"}.get(base.get("kind", ""), "ore"))
	if item.base in ["staff", "bow", "wand"]:
		key = "wood"
	var amount := roundi((1 + int(item.rarity) / 2.0) * host.gifts.factor(pid, "salvage"))
	if not add_materials(pid, {key: amount}):
		return "Не хватает места для материалов."
	p.inv.remove_at(index)
	return "Разобрано: %s ×%d." % [NAMES[key], amount]


## Превращает пять обычных ресурсов в один ресурс следующего тира.
func transmute(pid: int, material: String) -> String:
	var p: Dictionary = host.players[pid]
	var upgraded := "rich_" + material
	if not host.gifts.has(p, "transmute") or not NAMES.has(upgraded):
		return "Преобразование недоступно."
	if int(p.materials.get(material, 0)) < 5:
		return "Нужно пять ресурсов одного вида."
	p.materials[material] -= 5
	p.materials[upgraded] = int(p.materials.get(upgraded, 0)) + 1
	return "Получено: %s." % NAMES[upgraded]


## Записывает опыт общей и профильной профессии.
func gain_xp(pid: int, job: String, amount: int) -> void:
	var p: Dictionary = host.players[pid]
	var factor: float = host.gifts.factor(pid, "craft_xp") * host.gifts.factor(pid, "xp_" + job)
	p.professions[job] = minf(1000000, float(p.professions.get(job, 0.0)) + amount * factor)


## Эффекты еды, свитков и книг.
func consume(pid: int, item: Dictionary) -> String:
	var p: Dictionary = host.players[pid]
	match str(item.base):
		"meal":
			var amount := roundi(30.0 * host.gifts.factor(pid, "food") * host.gifts.factor(pid, "cook"))
			host.skills._heal(pid, amount)
			if host.gifts.has(p, "food_share"):
				for ally in host.talents.allies(pid, 120.0):
					host.skills._heal(ally, roundi(amount * 0.30))
			return "Вы отдохнули и поели."
		"scroll":
			host.gifts.buff(p, "dmg", 0.15 * (1.2 if host.gifts.has(p, "scroll_boost") else 1.0), 30.0)
			return "Свиток усилил ваши атаки."
		"book":
			host.skills.give_xp(pid, 30 if host.gifts.has(p, "scroll_boost") else 25)
			return "Книга дала боевой опыт."
	return ""



## Вставляет самоцвет в оружие из сумки.
func infuse(pid: int, uid: String) -> String:
	var p: Dictionary = host.players[pid]
	var i: int = host._find(p.inv, uid)
	if i < 0 or Items.slot_of(p.inv[i]) != "weapon" or p.inv[i].get("socketed", false):
		return "Нужно оружие из сумки без самоцвета."
	if int(p.materials.get("gem", 0)) <= 0:
		return "Нужен самоцвет."
	p.materials.gem -= 1
	p.inv[i].dmg += 1
	p.inv[i].socketed = true
	return "Самоцвет усилил оружие."


## Повышает качество работы с ростом опыта профессии.
static func proficiency(p: Dictionary, job: String) -> int:
	return clampi(floori(float(p.get("professions", {}).get(job, 0.0)) / 50.0), 0, 6)
