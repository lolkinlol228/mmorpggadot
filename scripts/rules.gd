extends Node

const Gifts := preload("res://scripts/gifts.gd")
## Правила развития героя: характеристики, расы, классы, умения, ресурсы (мана / ярость / энергия),
## штраф за чужую экипировку. Хост считает по этим формулам; клиент — только показывает.

const STATS := ["str", "agi", "vit", "spi", "int", "def", "luk", "spd"]
const STAT_NAMES := {"str": "Сила", "agi": "Ловкость", "vit": "Живучесть", "spi": "Дух",
	"int": "Интеллект", "def": "Стойкость", "luk": "Удача", "spd": "Скорость"}
## Баланс: каждое очко даёт примерно +3% к главному эффекту своей характеристики на 5–10 уровне.
## Точная прибавка следующего очка показывается в подсказке окна героя (считается по этим же формулам).
const STAT_HELP := {"str": "урон оружием: +1 за очко", "agi": "крит +0,8% и скорость атаки +1,8% за очко",
	"vit": "здоровье +8 и выносливость +3% за очко",
	"spi": "мана +6, перезарядка умений −2%, лечение +4% за очко",
	"int": "урон умений +3% за очко", "def": "броня +1,5 за очко (каждая единица снимает 0,5 урона с удара)",
	"luk": "крит +0,4%, сила крита +3%, редкие находки +1,5% за очко",
	"spd": "скорость бега +1% и уклонение +0,6% за очко"}
## Новые характеристики считаются от очков сверх базы 5 (вложенные + раса + класс).
const STAT_PER := {"str_dmg": 1.0, "agi_crit": 0.008, "agi_aspd": 0.018, "vit_hp": 8.0,
	"int_skill": 0.03, "def_armor": 1.5, "luk_crit": 0.004, "luk_crit_dmg": 0.03, "luk_find": 0.015,
	"spd_speed": 0.01, "spd_dodge": 0.006}
const BASE_STAT := 5
const POINTS_PER_LEVEL := 4
const XP_FOR_KILL := {"undead": 27, "slime": 8, "wolf": 18, "golem": 250}
const SHARE_XP_RADIUS := 320.0      # опыт получают все союзники рядом — играть вместе выгодно
const OFF_CLASS := 0.5              # чужое оружие и броня дают только половину характеристик
const SKILL_LEVELS := [1, 2, 4, 6]  # с какого уровня открываются 1-е…4-е умения класса
const SKILL_KEYS := ["1", "2", "3", "4"]
# Минимумы, чтобы враги оставались опасными при любой броне, дарах и баффах:
const ENEMY_MIN_DMG := 0.2          # удар врага после брони — не меньше 20% от его силы
const MIN_DMG_TAKEN := 0.15         # все множители защиты вместе — не ниже ×0.15 (кроме божественного щита)
# Парирование (ПКМ или F): только оружием ближнего боя. Удар в окно гасится, враг оглушён,
# следующий удар героя — ответный, сильнее. Удачное парирование снова готово почти сразу.
const PARRY := {"window": 0.3, "cd": 3.0, "cost": 20.0, "stun": 1.0, "riposte": 1.5, "riposte_time": 2.0, "rage": 10.0}

# Раса — внешность, небольшой бонус к характеристикам и пассивка. Умения даёт класс.
const RACES := {
	"human": {"name": "Человек", "stats": {"str": 1, "agi": 1, "vit": 1, "spi": 1}, "passive": "Опыт +10%", "xp_mult": 1.1},
	"elf": {"name": "Эльф", "stats": {"agi": 2, "spi": 2}, "passive": "Шанс крита +5%", "crit": 0.05},
	"dwarf": {"name": "Дварф", "stats": {"vit": 3, "str": 1, "def": 1}, "passive": "Броня +3", "armor": 3},
	"orc": {"name": "Орк", "stats": {"str": 3, "vit": 1}, "passive": "Урон +10%", "dmg_mult": 1.1},
	"undead": {"name": "Нежить", "stats": {"vit": 2, "spi": 2}, "passive": "Регенерация здоровья ×2", "regen_mult": 2.0},
	"felin": {"name": "Кошколюд", "stats": {"agi": 3, "str": 1, "spd": 1}, "passive": "Скорость бега +10%", "speed_mult": 1.1},
	"goblin": {"name": "Гоблин", "stats": {"agi": 2, "spi": 2, "luk": 2}, "passive": "Монет с врагов +30%", "coin_mult": 1.3},
}

const RES_NAMES := {"mana": "Мана", "rage": "Ярость", "energy": "Энергия"}
const RES_COLORS := {"mana": Color(0.35, 0.55, 1.0), "rage": Color(0.9, 0.25, 0.2), "energy": Color(0.95, 0.8, 0.25)}

# weapons — своё оружие (умения класса работают только с ним), armor — свой тип брони.
const CLASSES := {
	"warrior": {"name": "Воин", "role": "Танк: принимает удары на себя, копит ярость в бою",
		"weapons": ["sword", "axe"], "armor": ["plate"], "res": "rage", "stats": {"str": 2, "vit": 2, "def": 2}, "hp_mult": 1.15,
		"skills": ["smash", "whirl", "warcry", "bulwark"], "kit": ["sword", "armor"]},
	"mage": {"name": "Маг", "role": "Урон по площади и замедление издалека",
		"weapons": ["staff"], "armor": ["cloth"], "res": "mana", "stats": {"spi": 3, "agi": 1, "int": 3}, "hp_mult": 0.9,
		"skills": ["fireball", "frost_nova", "blink", "meteor"], "kit": ["staff", "robe"]},
	"priest": {"name": "Жрец", "role": "Лечит и защищает союзников",
		"weapons": ["wand", "staff"], "armor": ["cloth"], "res": "mana", "stats": {"spi": 3, "vit": 1, "int": 1, "def": 1}, "hp_mult": 0.95,
		"skills": ["holy_light", "smite", "barrier", "renew"], "kit": ["wand", "robe"]},
	"ranger": {"name": "Следопыт", "role": "Урон из лука с дальней дистанции",
		"weapons": ["bow"], "armor": ["leather"], "res": "energy", "stats": {"agi": 3, "str": 1, "spd": 2}, "hp_mult": 1.0,
		"skills": ["power_shot", "volley", "hunter_pace", "arrow_rain"], "kit": ["bow", "jerkin"]},
	"rogue": {"name": "Разбойник", "role": "Криты, скорость и добивание",
		"weapons": ["dagger", "sword"], "armor": ["leather"], "res": "energy", "stats": {"agi": 3, "str": 1, "luk": 2}, "hp_mult": 0.95,
		"skills": ["dirty_trick", "pounce", "blade_fan", "assassinate"], "kit": ["dagger", "jerkin"]},
	"paladin": {"name": "Паладин", "role": "Латы и молот: держит удар и лечит",
		"weapons": ["hammer", "sword"], "armor": ["plate"], "res": "mana", "stats": {"str": 2, "spi": 2, "def": 1, "int": 1}, "hp_mult": 1.1,
		"skills": ["holy_strike", "lay_hands", "valor_aura", "divine_shield"], "kit": ["hammer", "armor"]},
}

# Умения — данные, хост исполняет их по полю kind:
#   strike — удар по кругу: off (смещение вперёд), r (радиус), mult, crit
#   bolt   — снаряд по прямой: range, mult, aoe (радиус взрыва), crit
#   multi  — веер снарядов: count, spread (радианы между снарядами), range, mult
#   heal   — лечение: target self | lowest (самый раненый рядом) | allies (все рядом), base, spi (×Дух), radius
#   buff   — усиление: buff (имя), dur, allies (радиус; 0 — только себе)
#   blink  — перенос вперёд
# icon — клетка в листе Shikashi (ряд 3 — «особые приёмы»), cost — расход ресурса класса.
const SKILLS := {
	# воин
	"smash": {"name": "Сокрушение", "icon": Vector2i(11, 3), "cd": 6.0, "cost": 15, "kind": "strike",
		"off": 28.0, "r": 30.0, "mult": 2.5, "crit": 0.1, "desc": "Мощный удар вперёд: 250% урона"},
	"whirl": {"name": "Вихрь", "icon": Vector2i(4, 3), "cd": 8.0, "cost": 25, "kind": "strike",
		"off": 0.0, "r": 46.0, "mult": 1.2, "crit": 0.0, "desc": "Удар по всем врагам вокруг: 120% урона"},
	"warcry": {"name": "Боевой клич", "icon": Vector2i(6, 3), "cd": 35.0, "cost": 30, "kind": "buff",
		"buff": "warcry", "dur": 6.0, "allies": 120.0, "desc": "6 сек: урон +40% тебе и союзникам рядом"},
	"bulwark": {"name": "Глухая оборона", "icon": Vector2i(7, 3), "cd": 30.0, "cost": 0, "kind": "buff",
		"buff": "stoneskin", "dur": 6.0, "allies": 0.0, "desc": "6 сек: получаемый урон −60%"},
	# маг
	"fireball": {"name": "Огненный шар", "icon": Vector2i(9, 3), "cd": 2.5, "cost": 12, "kind": "bolt",
		"range": 220.0, "mult": 2.0, "aoe": 22.0, "crit": 0.0, "fx": "fire", "desc": "Шар огня: 200% урона и взрыв"},
	"frost_nova": {"name": "Ледяная волна", "icon": Vector2i(1, 3), "cd": 10.0, "cost": 20, "kind": "strike",
		"off": 0.0, "r": 56.0, "mult": 1.0, "crit": 0.0, "slow": 3.0, "desc": "Холод вокруг: 100% урона, враги замедлены на 3 сек"},
	"blink": {"name": "Скачок", "icon": Vector2i(14, 3), "cd": 10.0, "cost": 10, "kind": "blink",
		"desc": "Мгновенный перенос на 90 шагов вперёд"},
	"meteor": {"name": "Метеор", "icon": Vector2i(2, 4), "cd": 30.0, "cost": 40, "kind": "strike",
		"off": 70.0, "ground": 170.0, "r": 44.0, "mult": 4.0, "crit": 0.05, "delay": 0.55,
		"desc": "Камень с неба в точку прицела: 400% урона по площади"},
	# жрец
	"holy_light": {"name": "Святой свет", "icon": Vector2i(5, 3), "cd": 4.0, "cost": 14, "kind": "heal",
		"target": "lowest", "base": 25, "spi": 3.0, "radius": 160.0, "desc": "Лечит самого раненого рядом: 25 + Дух×3"},
	"smite": {"name": "Кара", "icon": Vector2i(15, 3), "cd": 2.5, "cost": 8, "kind": "bolt",
		"range": 200.0, "mult": 1.6, "aoe": 0.0, "crit": 0.0, "fx": "holy", "desc": "Луч света: 160% урона"},
	"barrier": {"name": "Щит веры", "icon": Vector2i(8, 3), "cd": 25.0, "cost": 25, "kind": "buff",
		"buff": "barrier", "dur": 6.0, "allies": 140.0, "desc": "6 сек: союзники рядом получают на 50% меньше урона"},
	"renew": {"name": "Обновление", "icon": Vector2i(12, 3), "cd": 30.0, "cost": 40, "kind": "heal",
		"target": "allies", "base": 40, "spi": 4.0, "radius": 160.0, "desc": "Лечит всех союзников рядом: 40 + Дух×4"},
	# следопыт
	"power_shot": {"name": "Меткий выстрел", "icon": Vector2i(3, 3), "cd": 6.0, "cost": 30, "kind": "bolt",
		"range": 300.0, "mult": 2.6, "aoe": 0.0, "crit": 0.15, "fx": "arrow", "desc": "Дальний выстрел: 260% урона, +15% крит"},
	"volley": {"name": "Залп", "icon": Vector2i(2, 3), "cd": 8.0, "cost": 35, "kind": "multi",
		"count": 3, "spread": 0.3, "range": 240.0, "mult": 1.0, "fx": "arrow", "desc": "Три стрелы веером по 100% урона"},
	"hunter_pace": {"name": "Поступь охотника", "icon": Vector2i(13, 3), "cd": 25.0, "cost": 20, "kind": "buff",
		"buff": "pounce", "dur": 5.0, "allies": 0.0, "desc": "5 сек: скорость +40%, рывки без выносливости"},
	"arrow_rain": {"name": "Град стрел", "icon": Vector2i(1, 3), "cd": 22.0, "cost": 50, "kind": "strike",
		"off": 110.0, "ground": 220.0, "r": 50.0, "mult": 2.2, "crit": 0.0, "delay": 0.35,
		"desc": "Град стрел в точку прицела: 220% урона по площади"},
	# разбойник
	"dirty_trick": {"name": "Подлый приём", "icon": Vector2i(0, 3), "cd": 12.0, "cost": 25, "kind": "buff",
		"buff": "dirty_trick", "dur": 6.0, "allies": 0.0, "desc": "Следующий удар в течение 6 сек — крит ×3"},
	"pounce": {"name": "Прыть", "icon": Vector2i(10, 3), "cd": 20.0, "cost": 20, "kind": "buff",
		"buff": "pounce", "dur": 5.0, "allies": 0.0, "desc": "5 сек: скорость +40%, рывки без выносливости"},
	"blade_fan": {"name": "Веер клинков", "icon": Vector2i(4, 3), "cd": 9.0, "cost": 35, "kind": "strike",
		"off": 0.0, "r": 40.0, "mult": 1.5, "crit": 0.1, "desc": "Клинки во все стороны: 150% урона"},
	"assassinate": {"name": "Смертельный удар", "icon": Vector2i(3, 3), "cd": 18.0, "cost": 50, "kind": "strike",
		"off": 26.0, "r": 24.0, "mult": 4.0, "crit": 0.25, "execute": 0.3,
		"desc": "400% урона вперёд, вдвое больше по врагу ниже 30% здоровья"},
	# паладин
	"holy_strike": {"name": "Удар света", "icon": Vector2i(15, 3), "cd": 5.0, "cost": 10, "kind": "strike",
		"off": 28.0, "r": 28.0, "mult": 1.8, "crit": 0.0, "leech": 0.2, "desc": "180% урона вперёд, 20% урона лечит тебя"},
	"lay_hands": {"name": "Возложение рук", "icon": Vector2i(5, 3), "cd": 20.0, "cost": 25, "kind": "heal",
		"target": "self", "base": 40, "spi": 4.0, "radius": 0.0, "desc": "Лечит тебя: 40 + Дух×4"},
	"valor_aura": {"name": "Аура доблести", "icon": Vector2i(6, 3), "cd": 35.0, "cost": 30, "kind": "buff",
		"buff": "warcry", "dur": 8.0, "allies": 140.0, "desc": "8 сек: урон +40% тебе и союзникам рядом"},
	"divine_shield": {"name": "Божественный щит", "icon": Vector2i(8, 3), "cd": 60.0, "cost": 35, "kind": "buff",
		"buff": "divine", "dur": 3.0, "allies": 0.0, "desc": "3 сек полной неуязвимости"},
}

# Базовая атака по стилю оружия: перезарядка мс, урон, радиус, шанс крита, дальность (для снарядов — длина полёта).
const ATTACKS := {"slash": [300, 1.0, 36.0, 0.10, 30.0], "chop": [470, 1.35, 42.0, 0.10, 28.0],
	"stab": [190, 0.8, 26.0, 0.22, 34.0], "bolt": [520, 0.9, 8.0, 0.08, 180.0], "shot": [460, 1.0, 6.0, 0.12, 230.0]}


## Куда бьёт умение-удар. ground — по прицелу (aim — вектор от героя к курсору), не дальше ground;
## иначе — на off шагов вперёд по направлению.
func skill_point(sk: Dictionary, origin: Vector2, dir: Vector2, aim: Vector2) -> Vector2:
	if sk.has("ground") and aim.length() > 1.0:
		return origin + aim.limit_length(float(sk.ground))
	return origin + dir * float(sk.get("off", 0.0))


## Насколько далеко бьёт умение — для подсказки прицела (круг дальности).
func skill_reach(sk: Dictionary) -> float:
	match str(sk.kind):
		"bolt", "multi":
			return float(sk.range)
		"heal":
			return float(sk.get("radius", 120.0))
		"strike":
			return float(sk.get("ground", sk.get("off", 0.0)))
	return 0.0


func race_of(p: Dictionary) -> Dictionary:
	return RACES.get(str(p.get("look", {}).get("race", "human")), RACES.human)


func class_id(p: Dictionary) -> String:
	var c := str(p.get("cls", "warrior"))
	return c if CLASSES.has(c) else "warrior"


func class_of(p: Dictionary) -> Dictionary:
	return CLASSES[class_id(p)]


func class_skills(p: Dictionary) -> Array:
	var native: Array = class_of(p).skills
	var extra := str(p.get("cross_skill", ""))
	if Gifts.has_flag(p, "cross_skill") and SKILLS.has(extra) and extra not in native:
		return native + [extra]
	return native


func skill_level(p: Dictionary, id: String) -> int:
	var i := class_skills(p).find(id)
	return SKILL_LEVELS[mini(i, SKILL_LEVELS.size() - 1)] if i >= 0 else 999


## Какие классы считают предмет своим (для подсказки). Пусто — подходит всем.
func classes_for(base: String) -> String:
	var b: Dictionary = Items.BASES.get(base, {})
	if b.get("slot", "") not in ["weapon", "head", "body"] or b.get("unique", false):
		return ""
	var kind := str(b.get("kind", ""))
	if b.slot != "weapon" and kind == "":
		return ""
	var names := PackedStringArray()
	for c in CLASSES.values():
		if (b.slot == "weapon" and Items.art_base(base) in c.weapons) or (kind != "" and kind in c.armor):
			names.append(c.name)
	return ", ".join(names)


## Свой ли предмет для класса героя. Уникальные трофеи и обувь подходят всем.
func fits(p: Dictionary, it) -> bool:
	if not (it is Dictionary) or it.is_empty() or not Items.BASES.has(it.base):
		return true
	var b: Dictionary = Items.BASES[it.base]
	if b.get("unique", false):
		return true
	if b.slot == "weapon":
		return Items.art_base(it.base) in class_of(p).weapons or Gifts.has_flag(p, "any_weapon")
	var kind := str(b.get("kind", ""))
	return kind == "" or kind in class_of(p).armor


## Парировать можно только оружием ближнего боя (меч, топор, кинжал, молот).
func can_parry(p: Dictionary) -> bool:
	var w = p.get("equip", {}).get("weapon")
	return w is Dictionary and Items.style_of(w) in ["slash", "chop", "stab"]


func has_class_weapon(p: Dictionary) -> bool:
	var w = p.get("equip", {}).get("weapon")
	return w is Dictionary and fits(p, w)


## Заклинатель в латах: умения дороже, мана восстанавливается вдвое медленнее.
func heavy_caster(p: Dictionary) -> bool:
	if class_of(p).res != "mana" or "plate" in class_of(p).armor:
		return false
	for it in p.get("equip", {}).values():
		if it is Dictionary and Items.kind_of(it) == "plate":
			return true
	return false


func _gear_sum(p: Dictionary, field: String) -> float:
	var s := 0.0
	for it in p.get("equip", {}).values():
		if it is Dictionary:
			if it.get("base", "") == "shield" and two_handed(p.get("equip", {}).get("weapon", {})) and not Gifts.has_flag(p, "titan_grip"):
				continue
			s += float(it.get(field, 0)) * (1.0 if fits(p, it) else OFF_CLASS)
	return s


func xp_to_next(level: int) -> int:
	return int(50 + 40 * pow(level - 1, 1.4))


func stat(p: Dictionary, s: String) -> int:
	return BASE_STAT + int(p.get("stats", {}).get(s, 0)) + int(race_of(p).stats.get(s, 0)) + int(class_of(p).stats.get(s, 0))


## Максимум здоровья с активными модификаторами хоста.
func max_hp(p: Dictionary, gift_factor: float = -1.0) -> int:
	return int((80 + stat(p, "vit") * STAT_PER.vit_hp + int(p.get("level", 1)) * 4) * float(class_of(p).hp_mult) * (Gifts.factor(p, "hp") if gift_factor < 0.0 else gift_factor))


func damage(p: Dictionary) -> float:
	return base_damage(p) * Gifts.factor(p, "dmg")


## Урон до применения даров.
func base_damage(p: Dictionary) -> float:
	var fists := 4.0 if not p.get("equip", {}).has("weapon") and Gifts.has_flag(p, "fists") else 0.0
	return (4.0 + fists + _gear_sum(p, "dmg") + stat(p, "str") * STAT_PER.str_dmg) * float(race_of(p).get("dmg_mult", 1.0))


func crit_chance(p: Dictionary) -> float:
	return clampf(base_crit_chance(p) + Gifts.mod(p, "crit"), 0.0, Gifts.CAPS.crit)


## Шанс крита до даров и потолка.
func base_crit_chance(p: Dictionary) -> float:
	return stat(p, "agi") * STAT_PER.agi_crit + float(race_of(p).get("crit", 0.0)) + extra(p, "luk") * STAT_PER.luk_crit


## Делитель перезарядки атаки.
func attack_speed(p: Dictionary, bonus: float = INF) -> float:
	return clampf(1.0 + stat(p, "agi") * STAT_PER.agi_aspd + (Gifts.mod(p, "aspd") if bonus == INF else bonus), 0.1, 1.0 + Gifts.CAPS.aspd)


func armor(p: Dictionary) -> int:
	if Gifts.has_flag(p, "no_armor"):
		return 0
	return int((_gear_sum(p, "armor") + int(race_of(p).get("armor", 0)) + extra(p, "def") * STAT_PER.def_armor) * Gifts.factor(p, "armor"))


func cd_mult(p: Dictionary) -> float:
	return maxf(Gifts.CAPS.cd_mult_min, (1.0 + Gifts.mod(p, "cd")) / (1.0 + stat(p, "spi") * 0.02))


func heal_power(p: Dictionary) -> float:
	return (1.0 + stat(p, "spi") * 0.04) * Gifts.factor(p, "heal")


func speed_mult(p: Dictionary) -> float:
	return minf(1.0 + Gifts.CAPS.speed, float(race_of(p).get("speed_mult", 1.0)) * Gifts.factor(p, "speed") * (1.0 + extra(p, "spd") * STAT_PER.spd_speed))


## Очки новой характеристики сверх базы (вложенные + раса + класс).
func extra(p: Dictionary, s: String) -> int:
	return maxi(0, stat(p, s) - BASE_STAT)


## Прибавка к урону умений от Интеллекта.
func skill_power(p: Dictionary) -> float:
	return extra(p, "int") * STAT_PER.int_skill


## Множитель крита до даров: ×2 и Удача.
func crit_mult(p: Dictionary) -> float:
	return 2.0 + extra(p, "luk") * STAT_PER.luk_crit_dmg


## Уклонение от Скорости (складывается с дарами, общий потолок Gifts.CAPS.dodge).
func dodge_bonus(p: Dictionary) -> float:
	return extra(p, "spd") * STAT_PER.spd_dodge


## Сдвиг к редким находкам от Удачи (складывается с дарами, потолок Gifts.CAPS.rare_find).
func luck_find(p: Dictionary) -> float:
	return extra(p, "luk") * STAT_PER.luk_find


func stamina_regen(p: Dictionary) -> float:
	return (1.0 + stat(p, "vit") * 0.03) * Gifts.factor(p, "stam_regen")


# ---------- ресурс класса ----------

func res_kind(p: Dictionary) -> String:
	return class_of(p).res


## Максимум ресурса с активными модификаторами хоста.
func res_max(p: Dictionary, mana_factor: float = -1.0) -> int:
	if res_kind(p) == "mana":
		return int((40 + stat(p, "spi") * 6 + int(p.get("level", 1)) * 3) * (Gifts.factor(p, "mana") if mana_factor < 0.0 else mana_factor))
	return 100


## Сколько ресурса восстанавливается в секунду (ярость не восстанавливается — она копится в бою).
func res_regen(p: Dictionary, mana_factor: float = -1.0) -> float:
	match res_kind(p):
		"mana":
			return (1.5 + stat(p, "spi") * 0.12) * (0.5 if heavy_caster(p) else 1.0) * (Gifts.factor(p, "mana_regen") if mana_factor < 0.0 else mana_factor)
		"energy":
			return 12.0 + stat(p, "agi") * 0.1
	return 0.0


func skill_cost(p: Dictionary, id: String) -> int:
	return int(ceil(float(SKILLS[id].get("cost", 0)) * (1.3 if heavy_caster(p) else 1.0) * (Gifts.factor(p, "mana_cost") if res_kind(p) == "mana" else 1.0)))


func skill_unlocked(p: Dictionary, id: String) -> bool:
	return int(p.get("level", 1)) >= skill_level(p, id)


## Оружие, для которого в обычном случае нужны две руки.
func two_handed(item: Dictionary) -> bool:
	return item.get("base", "") in ["staff", "bow", "hammer", "axe", "abyss_blade"]
