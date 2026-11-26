extends Node
## Условия, события и эффекты даров на хосте.

const Gifts := preload("res://scripts/gifts.gd")
var host
var tick_at := 0
var dot_at := 0

## Условия дара в момент события.
func cond(pid: int, when: String, ctx: Dictionary = {}) -> bool:
	var p: Dictionary = host.players[pid]
	var e: Dictionary = ctx.get("enemy", {})
	var kind := str(e.get("kind", ""))
	var weapon: Dictionary = p.get("equip", {}).get("weapon", {})
	match when:
		"": return true
		"low_hp": return ratio(p) < 0.35
		"still": return now() - int(p.get("moved_at", 0)) >= 500
		"night": return World.night > 0.5
		"day": return World.night < 0.5
		"group", "near_ally":
			return host.skills._allies_near(p.pos, 200.0 if when == "group" else 80.0).size() > 1
		"outnumbered", "one_enemy":
			var count := nearby(p.pos, 120.0).size()
			return count >= 3 if when == "outnumbered" else count == 1
		"target_low": return not e.is_empty() and ratio(e) < 0.5
		"vs_slime", "vs_wolf", "vs_golem": return when == "vs_" + kind
		"vs_big", "vs_elite": return kind == "golem"
		"blade": return weapon.get("base", "") in ["sword", "dagger", "abyss_blade"]
		"blunt": return weapon.get("base", "") == "hammer"
		"far_target": return not e.is_empty() and p.pos.distance_to(e.pos) > 120.0
		"not_hurt3": return now() - int(p.get("hurt_at", -3000)) >= 3000
	return false


## Сумма активных добавок с учётом условий и флагов.
func mod(pid: int, key: String, ctx: Dictionary = {}) -> float:
	var p: Dictionary = host.players[pid]
	var total := Gifts.mod(p, key)
	for id in p.gifts:
		var gift := Gifts.get_gift(id)
		if gift.has("when") and cond(pid, gift.when, ctx):
			total += Gifts.contribution(gift, key)
	if key in Gifts.COMBAT_KEYS:
		var all := 0.0
		if Gifts.has_flag(p, "lone_wolf"):
			all += -0.10 if cond(pid, "group") else 0.25
		if Gifts.has_flag(p, "lunatic"):
			all += 0.25 if cond(pid, "night") else -0.15
		total += -all if key == "cd" else all
	return total


## Действующий множитель с потолком итоговой добавки.
func factor(pid: int, key: String, ctx: Dictionary = {}) -> float:
	return maxf(0.0, 1.0 + minf(mod(pid, key, ctx), float(Gifts.CAPS.get(key, INF))))


## Текущее время хоста в мс.
func now() -> int:
	return Time.get_ticks_msec()


## Доля оставшегося здоровья.
func ratio(entity: Dictionary) -> float:
	return float(entity.hp) / maxf(1.0, float(entity.max_hp))


## Живые враги в радиусе.
func nearby(pos: Vector2, radius: float) -> Array:
	var result := []
	for id in host.enemies:
		var e: Dictionary = host.enemies[id]
		if e.hp > 0 and pos.distance_to(e.pos) <= radius:
			result.append(id)
	return result


## Смена состояния боя.
func combat(pid: int, ctx: Dictionary = {}) -> void:
	var p: Dictionary = host.players[pid]
	if p.has("gift_combat") and now() - int(p.gift_combat) >= 5000:
		p.erase("gift_combat")
		fire(pid, "combat_end")
	if not p.has("gift_combat"):
		p.gift_diamond = 0
		fire(pid, "combat_start", ctx)
	p.gift_combat = now()


## Обновление периодических эффектов и выхода из боя.
func update() -> void:
	var time := now()
	var tick := time >= tick_at
	if tick:
		tick_at = time + 1000
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		if p.has("gift_combat") and time - int(p.gift_combat) >= 5000:
			p.erase("gift_combat")
			fire(pid, "combat_end")
		if ratio(p) >= 0.35:
			p.gift_low = false
		if tick and p.hp > 0:
			var maximum := Rules.max_hp(p, factor(pid, "hp"))
			if maximum != p.max_hp:
				p.max_hp = maximum
				p.hp = mini(int(p.hp), maximum)
				host._all("c_hp", [pid, p.hp, p.max_hp, 0])
			fire(pid, "tick")
			var motion := {"speed": mod(pid, "speed"), "aspd": mod(pid, "aspd"), "stam_regen": mod(pid, "stam_regen")}
			if motion != p.get("gift_motion", {}):
				p.gift_motion = motion
				host._to(pid, "c_gift_motion", [motion])
	if time >= dot_at:
		dot_at = time + 500
		tick_dots(time)


## Событие проверяет активность, шанс и интервал каждого дара.
func fire(pid: int, event: String, ctx: Dictionary = {}) -> void:
	if not host.players.has(pid):
		return
	var p: Dictionary = host.players[pid]
	var icd: Dictionary = p.get_or_add("gift_icd", {})
	for id in p.gifts:
		var gift := Gifts.get_gift(id)
		var proc: Array = gift.get("proc", [])
		if proc.size() != 4 or gift.get("flag", "") == "staff":
			continue
		if proc[0] != event and not (event == "parry" and gift.get("flag") == "counter_parry"):
			continue
		if not cond(pid, gift.get("when", ""), ctx) or randf() >= float(proc[1]):
			continue
		if event == "hit":
			if now() < int(icd.get(id, 0)):
				continue
			icd[id] = now() + int(Gifts.PROC_ICD * 1000.0)
		effect(pid, str(proc[2]), float(proc[3]), ctx)


## Обновляет временную добавку героя.
func buff(p: Dictionary, key: String, value: float, seconds: float) -> void:
	var values: Dictionary = p.get_or_add("gift_buffs", {})
	values[key] = [value, now() + int(seconds * 1000.0)]
	p.buffs["gift_" + key] = values[key][1]
	if key == "speed" or key == "aspd":
		host._send_self(int(p.peer_id))


## Активная добавка временного эффекта.
func buff_value(p: Dictionary, key: String) -> float:
	var value: Array = p.get("gift_buffs", {}).get(key, [0.0, 0])
	return float(value[0]) if now() < int(value[1]) else 0.0


## Выполняет эффект в контексте исходного события.
func effect(pid: int, key: String, value: float, ctx: Dictionary) -> void:
	var p: Dictionary = host.players[pid]
	var eid := int(ctx.get("eid", -1))
	var e: Dictionary = host.enemies.get(eid, {})
	var dmg := float(ctx.get("damage", 0))
	match key:
		"buff_dmg", "buff_aspd", "buff_speed": buff(p, key.trim_prefix("buff_"), value, 4.0)
		"stack_dmg": buff(p, "stack_dmg", minf(0.5, buff_value(p, "stack_dmg") + value), 5.0)
		"next_hit_mult": p.gift_next_hit = maxf(value, float(p.get("gift_next_hit", 1.0)))
		"bleed", "poison", "burn", "bleed_stack":
			add_dot(pid, e, key, value, ctx)
		"burn_near":
			for other in nearby(p.pos, 80.0):
				add_dot(pid, host.enemies[other], "burn", value, ctx)
		"stun", "slow":
			if not e.is_empty():
				var duration := value * (float(Gifts.BOSS_RULES.cc_mult) if e.kind == "golem" else 1.0)
				e[key + "_until"] = maxi(int(e.get(key + "_until", 0)), now() + int(duration * 1000.0))
		"knockback":
			if not e.is_empty() and e.kind != "golem":
				host._step(e, (e.pos - p.pos).normalized() * value, Items.ENEMIES[e.kind])
		"weaken", "sunder":
			if not e.is_empty():
				e[key] = [value, now() + 5000]
		"repeat":
			deal(pid, eid, int(ctx.get("raw_damage", dmg)))
		"whirl", "quake":
			for other in nearby(p.pos, 46.0 if key == "whirl" else 60.0):
				deal(pid, other, maxi(1, int(dmg * value)))
		"chain":
			var origin: Vector2 = ctx.get("enemy", {}).get("pos", p.pos)
			var targets := nearby(origin, 140.0)
			targets.erase(eid)
			targets.sort_custom(func(a, b): return origin.distance_squared_to(host.enemies[a].pos) < origin.distance_squared_to(host.enemies[b].pos))
			for other in targets.slice(0, int(value)):
				var target: Vector2 = host.enemies[other].pos
				host._all("c_shot", [origin, target, "arcane", 0.0])
				deal(pid, other, maxi(1, int(dmg)))
				origin = target
		"instakill":
			if not e.is_empty() and e.kind != "golem":
				deal(pid, eid, int(e.hp))
		"mana": host.skills.add_res(p, p.res_max * value)
		"repeat_skill": host.skills.perform(pid, ctx.id, ctx.dir, true)
		"cd_reset": p.cds[ctx.id] = 0
		"cd_all":
			for id in p.cds:
				if id != ctx.id and int(p.cds[id]) > now():
					p.cds[id] = maxi(now(), int(p.cds[id]) - int(value * 1000.0))
		"heal": host.skills._heal(pid, int(p.max_hp * value))
		"heal_allies":
			for other in host.skills._allies_near(p.pos, 120.0):
				if other != pid:
					host.skills._heal(other, int(host.players[other].max_hp * value))
		"delayed_heal":
			await get_tree().create_timer(3.0).timeout
			if host.players.get(pid) == p:
				host.skills._heal(pid, int(dmg * value))
		"shield_from_dmg": shield(pid, int(dmg * value))
		"invuln": p.invuln_until = maxi(int(p.get("invuln_until", 0)), now() + int(value * 1000.0))
		"self_dmg":
			p.hp = maxi(1, int(p.hp) - int(p.max_hp * value))
			health_events(pid, ctx)
			host._all("c_hp", [pid, p.hp, p.max_hp, 0])
		"coin_mult": ctx.coin_mult *= value
		"gold_drop": host.drop(Items.make_coins(maxi(1, int(ctx.coins * value))), ctx.enemy.pos)
		"dash_dmg":
			var from: Vector2 = ctx.from
			var end: Vector2 = ctx.end
			for other in nearby(from, from.distance_to(end) + 26.0):
				var pos: Vector2 = host.enemies[other].pos
				if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, from, end)) <= 26.0:
					deal(pid, other, int(Rules.damage(p) * value))
		"reflect": deal(pid, eid, int(dmg * value))
		"parry_reset":
			p.parry_ready = 0
			p.gift_riposte = value


## Меняет щит и сообщает владельцу.
func shield(pid: int, amount: int) -> void:
	var p: Dictionary = host.players[pid]
	p.shield = maxi(0, int(p.get("shield", 0)) + amount)
	host._to(pid, "c_shield", [p.shield])


## Вторичный урон без повторного запуска событий удара.
func deal(pid: int, eid: int, damage: int) -> void:
	var e: Dictionary = host.enemies.get(eid, {})
	if e.is_empty() or e.hp <= 0 or damage <= 0:
		return
	e.hp = maxi(0, int(e.hp) - damage)
	host._all("c_enemy_hit", [eid, e.hp, damage, false])
	if e.hp <= 0:
		host._kill(eid, pid)


## Добавляет или обновляет источник периодического урона.
func add_dot(pid: int, e: Dictionary, key: String, value: float, ctx: Dictionary) -> void:
	if e.is_empty() or e.hp <= 0:
		return
	var dots: Array = e.get_or_add("gift_dots", [])
	var dps := float(Rules.damage(host.players[pid])) * value * factor(pid, "dot", ctx)
	var expiry := now() + 4000
	for dot in dots:
		if dot.pid == pid and dot.key == key and key != "bleed_stack":
			dot.expiry = expiry
			dot.dps = dps
			return
	if dots.size() >= Gifts.DOT_MAX_STACKS:
		dots.pop_front()
	dots.append({"pid": pid, "key": key, "dps": dps, "expiry": expiry})


## Периодический урон суммируется, с общим потолком по боссу.
func tick_dots(time: int) -> void:
	for eid in host.enemies.keys():
		var e: Dictionary = host.enemies[eid]
		var dots: Array = e.get("gift_dots", [])
		var budget := float(e.max_hp) * float(Gifts.BOSS_RULES.dot_max_frac) * 0.5 if e.kind == "golem" else INF
		var carry := float(e.get("gift_dot_fraction", 0.0))
		for dot in dots.duplicate():
			if time > int(dot.expiry):
				dots.erase(dot)
				continue
			var portion := minf(budget, float(dot.dps) * 0.5)
			budget -= portion
			carry += portion
			deal(dot.pid, eid, int(carry))
			carry = fmod(carry, 1.0)
		e.gift_dot_fraction = carry



## Итоговый множитель урона от даров на исходном ударе.
func attack_factor(pid: int, eid: int, skill: bool, ctx: Dictionary) -> float:
	var p: Dictionary = host.players[pid]
	var multiplier := 1.0 + mod(pid, "dmg", ctx) + buff_value(p, "dmg") + buff_value(p, "stack_dmg")
	if skill:
		multiplier += mod(pid, "skill_dmg", ctx)
		if Gifts.has_flag(p, "mana_scaling") and Rules.res_kind(p) == "mana":
			multiplier += floorf(10.0 * float(p.res) / maxf(1.0, float(p.res_max))) * 0.01
	if Gifts.has_flag(p, "berserk"):
		multiplier += (1.0 - ratio(p)) * 0.5
	if Gifts.has_flag(p, "night_owl"):
		multiplier += 0.10 if cond(pid, "night") else -0.05
	if Gifts.has_flag(p, "fate_blade"):
		multiplier += float(p.gift_state.get("fate_blade", 0)) * 0.0001
	if Gifts.has_flag(p, "kill_streak"):
		var kills: Array = p.get("gift_kills", [])
		while not kills.is_empty() and now() - int(kills.front()) >= 60000:
			kills.pop_front()
		multiplier += mini(kills.size(), 25) * 0.01
	p.gift_attacks = int(p.get("gift_attacks", 0)) + 1
	if Gifts.has_flag(p, "momentum"):
		p.gift_momentum = mini(10, int(p.get("gift_momentum", 0)) + 1) if eid == int(p.get("gift_target", -1)) else 0
		p.gift_target = eid
		multiplier += float(p.gift_momentum) * 0.03
	if Gifts.has_flag(p, "combo4") and int(p.gift_attacks) % 4 == 0:
		multiplier *= 1.8
	multiplier *= float(p.get("gift_next_hit", 1.0))
	p.erase("gift_next_hit")
	multiplier = clampf(multiplier, 0.0, 1.0 + Gifts.CAPS.dmg)
	if Gifts.has_flag(p, "random_dmg"):
		multiplier *= randf_range(0.3, 2.2)
	return minf(multiplier, 1.0 + Gifts.CAPS.dmg)


## Дополнительные удары без повторного запуска даров удара.
func after_attack(pid: int, eid: int, damage: int, ctx: Dictionary) -> void:
	var p: Dictionary = host.players[pid]
	if Gifts.has_flag(p, "cleave"):
		for other in nearby(ctx.enemy.pos, 46.0):
			if other != eid:
				deal(pid, other, int(damage * 0.4))
	if Gifts.has_flag(p, "echo5") and int(p.gift_attacks) % 5 == 0:
		deal(pid, eid, int(ctx.get("raw_damage", damage)))


## Защитные эффекты после расчёта брони.
func protect(pid: int, dealt: int, floor_damage: int) -> int:
	var p: Dictionary = host.players[pid]
	var time := now()
	if Gifts.has_flag(p, "diamond3") and int(p.gift_diamond) < 3:
		p.gift_diamond += 1
		dealt = maxi(floor_damage, int(dealt * 0.1))
	if Gifts.has_flag(p, "dmg_cap25"):
		dealt = maxi(floor_damage, mini(dealt, maxi(1, int(p.max_hp * 0.25))))
	if Gifts.has_flag(p, "mana_shield10") and Rules.res_kind(p) == "mana":
		var absorbed := mini(int(p.res), mini(dealt - floor_damage, int(dealt * 0.10)))
		host.skills.add_res(p, -absorbed)
		dealt -= absorbed
	var shielded := mini(dealt - floor_damage, int(p.get("shield", 0) * factor(pid, "block")))
	if shielded > 0:
		shield(pid, -ceili(shielded / maxf(0.01, factor(pid, "block"))))
		dealt -= shielded
	if dealt >= p.hp and Gifts.has_flag(p, "cheat_death300") and time >= int(p.get("gift_cheat_at", 0)):
		p.gift_cheat_at = time + 300000
		return int(p.hp) - 1
	return dealt


## Отслеживает пересечение порога здоровья и одноразовое воскрешение.
func health_events(pid: int, ctx: Dictionary) -> void:
	var p: Dictionary = host.players[pid]
	if ratio(p) < 0.35 and not p.get("gift_low", false):
		p.gift_low = true
		fire(pid, "low_hp", ctx)
	if p.hp > 0:
		return
	fire(pid, "death", ctx)
	p.erase("gift_combat")
	if int(p.get("shield", 0)) > 0:
		shield(pid, -int(p.shield))
	if Gifts.has_flag(p, "self_revive600") and now() >= int(p.get("gift_revive_at", 0)):
		p.gift_revive_at = now() + 600000
		p.hp = maxi(1, int(p.max_hp * 0.4))
		p.gift_low = false
