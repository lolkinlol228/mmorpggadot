extends RefCounted
## Реакции врагов на дары, элитные враги и дальние атаки.

const Sites := preload("res://scripts/adventure_sites.gd")
var host


## Ищет цель с учётом угрозы, звериных даров и проклятий.
func target(enemy: Dictionary, stats: Dictionary) -> int:
	var result := -1
	var score := INF
	var curse := false
	var elite := false
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		if p.hp <= 0 or Sites.is_safe(World, p.pos):
			continue
		if Sites.MINE.has_point(p.pos) != Sites.MINE.has_point(enemy.pos):
			continue
		if Sites.MINE.has_point(enemy.pos) and Sites.mine_wall_between(enemy.pos, p.pos):
			continue
		if (enemy.kind == "undead") != Sites.CAVE.has_point(p.pos):
			continue
		var distance: float = enemy.pos.distance_to(p.pos)
		if distance <= 150.0:
			curse = curse or host.gifts.has(p, "enemies_stronger25")
			elite = elite or host.gifts.has(p, "all_elite")
		var hunted: bool = enemy.kind in ["golem", "warden"] and host.gifts.has(p, "boss_aggro_loot")
		if distance > float(stats.aggro) and not hunted:
			continue
		if enemy.kind == "wolf" and host.gifts.has(p, "beast_passive") and not enemy.get("attacked_by", {}).has(pid):
			continue
		var weighted := distance * (0.55 if host.gifts.has(p, "threat_up") else 1.0) - (10000.0 if hunted else 0.0)
		if weighted < score:
			score = weighted
			result = pid
	enemy.gift_cursed = curse
	if elite and enemy.kind not in ["golem", "warden"] and not enemy.get("elite", false):
		enemy.elite = true
		var extra := roundi(enemy.max_hp * 0.5)
		enemy.max_hp += extra
		enemy.hp += extra
		host._all("c_enemy_elite", [enemy.id, enemy.hp, enemy.max_hp])
	return result


## Двигает врага, применяет страх и отвлекает атакой по копии.
func engage(eid: int, pid: int, stats: Dictionary, delta: float) -> void:
	var e: Dictionary = host.enemies[eid]
	var p: Dictionary = host.players[pid]
	var now: int = host.gifts.now()
	var decoy := now < int(p.get("decoy_until", 0))
	var point: Vector2 = p.get("decoy_pos", p.pos) if decoy else p.pos
	var distance: float = e.pos.distance_to(point)
	var slowdown := float(e.get("slow_factor", 0.5)) if int(e.get("slow_until", 0)) > now else 1.0
	var velocity: Vector2 = (point - e.pos).normalized() * float(stats.speed) * slowdown * delta
	if e.kind == "wolf" and not e.get("elite", false) and host.gifts.has(p, "fear_weak") and float(p.max_hp) > float(e.max_hp):
		host._step(e, -velocity, stats)
		return
	var ranged: bool = e.kind == "undead" and distance > 35.0
	var reach: float = 120.0 if ranged else float(stats.radius) + 16.0
	if distance > reach:
		host._step(e, velocity, stats)
	elif e.cd <= 0.0:
		e.cd = float(stats.cooldown) / slowdown
		if decoy:
			host._all("c_world_pulse", [point, 12.0, Color.LIGHT_STEEL_BLUE])
			return
		var weaken: Array = e.get("weaken", [0.0, 0])
		var power := maxf(0.0, 1.0 - float(weaken[0])) if now < int(weaken[1]) else 1.0
		power *= 1.25 if e.gift_cursed else 1.0
		power *= 1.35 if e.get("elite", false) else 1.0
		if ranged:
			host._all("c_shot", [e.pos, point, "arcane", 0.0])
		host._hurt_player(pid, maxi(1, roundi(float(stats.dmg) * power)), eid, "ranged" if ranged else "melee")
