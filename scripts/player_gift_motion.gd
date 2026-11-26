extends RefCounted
## Параметры движения и выносливости владельца героя.

const Gifts := preload("res://scripts/gifts.gd")


## Скорость бега с учётом текущих эффектов.
static func speed(p: Dictionary, hud) -> float:
	var temporary := float(p.get("gift_speed", 0.0)) if hud.skills.has_buff("gift_speed") else 0.0
	var coward := 0.25 if Gifts.has_flag(p, "coward") and float(p.hp) < float(p.max_hp) * 0.4 else 0.0
	var mods := float(p.get("gift_motion", {}).get("speed", Gifts.mod(p, "speed")))
	var pounce := 0.4 * float(p.get("gift_buff_power", {}).get("pounce", 1.0)) if hud.skills.has_buff("pounce") else 0.0
	return clampf(float(Rules.race_of(p).get("speed_mult", 1.0)) * (1.0 + mods + temporary + coward + pounce), 0.1, 1.0 + Gifts.CAPS.speed)


## Расход выносливости за секунду спринта.
static func sprint_cost(p: Dictionary) -> float:
	return 0.0 if Gifts.has_flag(p, "free_sprint") else 26.0 * Gifts.factor(p, "sprint_cost")


## Скорость атаки для локального таймера.
static func attack_speed(p: Dictionary, hud) -> float:
	var temporary := float(p.get("gift_aspd", 0.0)) if hud.skills.has_buff("gift_aspd") else 0.0
	var mods := float(p.get("gift_motion", {}).get("aspd", Gifts.mod(p, "aspd")))
	return Rules.attack_speed(p, mods + temporary)



## Восстановление выносливости с учётом условий хоста.
static func stamina_regen(p: Dictionary) -> float:
	var mods := float(p.get("gift_motion", {}).get("stam_regen", Gifts.mod(p, "stam_regen")))
	return (1.0 + Rules.stat(p, "vit") * 0.03) * maxf(0.0, 1.0 + mods)
