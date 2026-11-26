extends Node
## Правила развития героя: характеристики, бонусы рас, опыт и уровни, умения.
## Хост считает по этим формулам урон, здоровье и перезарядки; клиент — только показывает.

const STATS := ["str", "agi", "vit", "spi"]
const STAT_NAMES := {"str": "Сила", "agi": "Ловкость", "vit": "Живучесть", "spi": "Дух"}
const STAT_HELP := {"str": "+0,6 к урону за очко", "agi": "криты и скорость атаки",
	"vit": "+6 здоровья, быстрее выносливость", "spi": "короче перезарядка умений, сильнее лечение"}
const BASE_STAT := 5
const POINTS_PER_LEVEL := 3
const XP_FOR_KILL := {"slime": 8, "wolf": 18, "golem": 250}
const SHARE_XP_RADIUS := 320.0      # опыт получают все союзники рядом — играть вместе выгодно

const RACES := {
	"human": {"name": "Человек", "stats": {"str": 1, "agi": 1, "vit": 1, "spi": 1}, "skill": "second_wind",
		"passive": "Опыт +10%", "xp_mult": 1.1},
	"elf": {"name": "Эльф", "stats": {"agi": 2, "spi": 2}, "skill": "blink",
		"passive": "Шанс крита +5%", "crit": 0.05},
	"dwarf": {"name": "Дварф", "stats": {"vit": 3, "str": 1}, "skill": "stoneskin",
		"passive": "Броня +3", "armor": 3},
	"orc": {"name": "Орк", "stats": {"str": 3, "vit": 1}, "skill": "warcry",
		"passive": "Урон +10%", "dmg_mult": 1.1},
	"undead": {"name": "Нежить", "stats": {"vit": 2, "spi": 2}, "skill": "drain",
		"passive": "Регенерация здоровья ×2", "regen_mult": 2.0},
	"felin": {"name": "Кошколюд", "stats": {"agi": 3, "str": 1}, "skill": "pounce",
		"passive": "Скорость бега +10%", "speed_mult": 1.1},
	"goblin": {"name": "Гоблин", "stats": {"agi": 2, "spi": 2}, "skill": "dirty_trick",
		"passive": "Монет с врагов +30%", "coin_mult": 1.3},
}

# icon — клетка в листе Shikashi (ряд 3 — «особые приёмы»); lvl — с какого уровня доступно
const SKILLS := {
	"whirl": {"name": "Вихрь", "icon": Vector2i(1, 3), "cd": 8.0, "lvl": 2, "key": "1",
		"desc": "Удар по всем врагам вокруг: 120% урона"},
	"smash": {"name": "Сокрушение", "icon": Vector2i(13, 3), "cd": 6.0, "lvl": 3, "key": "2",
		"desc": "Мощный удар вперёд: 250% урона"},
	"mend": {"name": "Перевязка", "icon": Vector2i(6, 3), "cd": 20.0, "lvl": 4, "key": "3",
		"desc": "Лечит 30 + Дух×3 здоровья"},
	"second_wind": {"name": "Второе дыхание", "icon": Vector2i(5, 3), "cd": 40.0, "dur": 1.0,
		"desc": "+30 здоровья и полная выносливость"},
	"blink": {"name": "Лунный шаг", "icon": Vector2i(14, 3), "cd": 10.0, "dur": 0.4,
		"desc": "Мгновенный перенос на 90 шагов вперёд"},
	"stoneskin": {"name": "Каменная кожа", "icon": Vector2i(8, 3), "cd": 30.0, "dur": 6.0,
		"desc": "6 сек: получаемый урон −60%"},
	"warcry": {"name": "Боевой клич", "icon": Vector2i(9, 3), "cd": 35.0, "dur": 6.0,
		"desc": "6 сек: урон +40% тебе и союзникам рядом"},
	"drain": {"name": "Похищение жизни", "icon": Vector2i(0, 3), "cd": 25.0, "dur": 8.0,
		"desc": "8 сек: 35% нанесённого урона лечит тебя"},
	"pounce": {"name": "Кошачья прыть", "icon": Vector2i(12, 3), "cd": 25.0, "dur": 5.0,
		"desc": "5 сек: скорость +40%, рывки без выносливости"},
	"dirty_trick": {"name": "Подлый приём", "icon": Vector2i(3, 3), "cd": 15.0, "dur": 6.0,
		"desc": "Следующий удар в течение 6 сек — крит ×3"},
}
const COMMON_SKILLS := ["whirl", "smash", "mend"]


func race_of(p: Dictionary) -> Dictionary:
	return RACES.get(str(p.get("look", {}).get("race", "human")), RACES.human)


func race_skill(p: Dictionary) -> String:
	return race_of(p).skill


func xp_to_next(level: int) -> int:
	return int(50 + 40 * pow(level - 1, 1.4))


func stat(p: Dictionary, s: String) -> int:
	return BASE_STAT + int(p.get("stats", {}).get(s, 0)) + int(race_of(p).stats.get(s, 0))


func max_hp(p: Dictionary) -> int:
	return 80 + stat(p, "vit") * 6 + int(p.get("level", 1)) * 4


func damage(p: Dictionary) -> float:
	var r := race_of(p)
	return (4.0 + Items.total_dmg(p.equip) + stat(p, "str") * 0.6) * float(r.get("dmg_mult", 1.0))


func crit_chance(p: Dictionary) -> float:
	return stat(p, "agi") * 0.006 + float(race_of(p).get("crit", 0.0))


func attack_speed(p: Dictionary) -> float:
	return 1.0 + stat(p, "agi") * 0.012          # делитель перезарядки атаки


func armor(p: Dictionary) -> int:
	return Items.total_armor(p.equip) + int(race_of(p).get("armor", 0))


func cd_mult(p: Dictionary) -> float:
	return 1.0 / (1.0 + stat(p, "spi") * 0.02)


func heal_power(p: Dictionary) -> float:
	return 1.0 + stat(p, "spi") * 0.04


func speed_mult(p: Dictionary) -> float:
	return float(race_of(p).get("speed_mult", 1.0))


func stamina_regen(p: Dictionary) -> float:
	return 1.0 + stat(p, "vit") * 0.03


func skill_unlocked(p: Dictionary, id: String) -> bool:
	if id == race_skill(p):
		return true
	return id in COMMON_SKILLS and int(p.get("level", 1)) >= int(SKILLS[id].lvl)
