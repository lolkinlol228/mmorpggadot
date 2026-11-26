extends RefCounted
## Особые механики даров, союзники и эффекты окружения на хосте.

const Gifts := preload("res://scripts/gifts.gd")
const Sites := preload("res://scripts/adventure_sites.gd")
const ALLY_RANGE := 150.0
const COLORS := {"cold": Color.LIGHT_SKY_BLUE, "fire": Color.ORANGE_RED, "poison": Color.YELLOW_GREEN, "trap": Color.SANDY_BROWN}

var host


## Живые союзники возле героя без включения самого героя.
func allies(pid: int, radius: float = ALLY_RANGE) -> Array:
	if not host.players.has(pid):
		return []
	var p: Dictionary = host.players[pid]
	var result := []
	for other in host.players:
		var ally: Dictionary = host.players[other]
		if other != pid and ally.hp > 0 and p.pos.distance_to(ally.pos) <= radius:
			result.append(other)
	return result


## Боевые и групповые добавки, без рекурсивного распространения аур.
func bonus(pid: int, key: String, ctx: Dictionary) -> float:
	var p: Dictionary = host.players[pid]
	var nearby := allies(pid)
	var total := 0.0
	if key in Gifts.COMBAT_KEYS:
		if host.gifts.has(p, "king"):
			total += -0.10 if key == "cd" else 0.10
		if host.gifts.has(p, "devourer") and key in ["dmg", "hp"]:
			total += int(p.gift_state.get("devourer", 0)) * 0.02
		if host.gifts.has(p, "vampire"):
			if key == "hp" and World.night < 0.5:
				total -= 0.20
			elif key == "dmg" and World.night > 0.5:
				total += 0.20
	if key == "dmg":
		if host.gifts.has(p, "gold_power"):
			total += mini(20, floori(int(p.coins) / 2000.0)) * 0.01
		if host.gifts.has(p, "pack"):
			total += mini(3, nearby.size()) * 0.04
		total += host.gifts.buff_value(p, "royal_rage")
	if key == "speed" and host.gifts.has(p, "rally"):
		for other in nearby:
			if host.gifts.ratio(host.players[other]) < 0.30:
				total += 0.20
				break
	for other in nearby:
		var ally: Dictionary = host.players[other]
		if key in Gifts.COMBAT_KEYS and host.gifts.has(ally, "king"):
			total += -0.10 if key == "cd" else 0.10
		if key in ["armor", "dmg"] and host.gifts.has(ally, "aura_banner"):
			total += 0.10
		if key == "stam_regen" and host.gifts.has(ally, "aura_stam"):
			total += 0.15
		if key == "xp" and host.gifts.has(ally, "aura_xp"):
			total += 0.20
		if key == "dmg":
			if host.gifts.has(ally, "aura_dmg8"):
				total += 0.08
			if host.gifts.has(ally, "pack"):
				total += mini(3, allies(other).size()) * 0.04
		if host.gifts.has(ally, "share_gifts"):
			total += host.gifts.personal_mod(other, key, ctx, false) * 0.5
		if key in ["loot", "rare_find", "mega_rare", "mythic_find"] and host.gifts.has(ally, "share_loot"):
			total += maxf(0.10 if key == "loot" else 0.0, host.gifts.personal_mod(other, key, ctx, false))
	return total


## Обновляет таймеры, окружение и источники периодических эффектов.
func tick(pid: int, time: int) -> void:
	var p: Dictionary = host.players[pid]
	var modified := false
	var temporary: Dictionary = p.get_or_add("temp_gifts", {})
	for id in temporary.keys():
		if int(temporary[id]) <= time:
			temporary.erase(id)
			if not host.gifts.has(p, "cross_skill"):
				p.cross_skill = ""
			modified = true
	if host.gifts.has(p, "hourly_gift") and time >= int(p.get("gift_hour_at", 0)):
		var excluded := Gifts.ids(p)
		var id := Gifts.roll_one(excluded)
		if id != "":
			temporary[id] = time + 3600000
			host._to(pid, "c_announce", ["На час получен дар: %s" % Gifts.get_gift(id).name, Color.MEDIUM_PURPLE])
			modified = true
		p.gift_hour_at = time + 3600000
	if host.gifts.has(p, "demon_tax") and time >= int(p.get("gift_tax_at", time + 600000)):
		p.coins -= floori(p.coins * 0.30)
		p.gift_tax_at = time + 600000
		host._to(pid, "c_announce", ["Демон забрал 30% монет.", Color.TOMATO])
		modified = true
	if not p.has("gift_tax_at"):
		p.gift_tax_at = time + 600000
	if modified:
		host._send_self(pid)
	for camp in Sites.CAMPS:
		if p.pos.distance_to(Sites.CAMPS[camp]) <= 65.0 and not p.visited.has(camp):
			p.visited[camp] = true
			host._send_self(pid)
	if host.gifts.has(p, "heal_aura"):
		for ally in allies(pid):
			host.skills.heal_fraction(ally, float(host.players[ally].max_hp) * 0.01, "aura")
	if host.gifts.has(p, "orbit"):
		var angle := time / 750.0
		for i in 2:
			var point: Vector2 = p.pos + Vector2.from_angle(angle + i * PI) * 32.0
			host._all("c_world_pulse", [point, 8.0, Color.MEDIUM_PURPLE])
			for eid in host.gifts.nearby(point, 20.0):
				host.gifts.deal(pid, eid, maxi(1, int(Rules.damage(p) * 0.18)))
	if host.gifts.has(p, "tree_strike") and Sites.forest(p.pos) and randf() < 0.22:
		for eid in host.gifts.nearby(p.pos, 100.0):
			var target: Vector2 = host.enemies[eid].pos
			host._all("c_world_pulse", [target, 20.0, Color.SEA_GREEN])
			host.gifts.deal(pid, eid, maxi(1, int(Rules.damage(p) * 0.35)))
			break
	companion_tick(pid, time)
	for hazard in Sites.HAZARDS:
		if p.pos.distance_to(hazard[1]) <= 38.0:
			hazard_hit(pid, hazard[0])
			if p.hp <= 0:
				break


## Эффекты холода, отравления, огня и ловушек.
func hazard_hit(pid: int, kind: String) -> void:
	var p: Dictionary = host.players[pid]
	if (kind == "poison" and host.gifts.has(p, "poison_immune")) or (kind == "fire" and host.gifts.has(p, "fire_immune")):
		return
	var scale := 0.5 if kind == "cold" and host.gifts.has(p, "cold_resist") else 1.0
	host._hurt_player(pid, maxi(1, roundi(7 * scale)), -1, kind)
	if kind == "trap" or kind == "cold":
		apply_control(pid, kind, scale)
	host._all("c_world_pulse", [p.pos, 16.0, COLORS[kind]])


## Сопротивление длительности контроля и иммунитет к оглушению и отбрасыванию.
func apply_control(pid: int, kind: String, scale: float) -> void:
	var p: Dictionary = host.players[pid]
	if p.hp <= 0 or (kind == "trap" and host.gifts.has(p, "unstoppable")):
		return
	var duration := 1.5 * scale * clampf(1.0 - host.gifts.mod(pid, "cc_resist"), 0.0, 1.0)
	if duration <= 0.0:
		return
	if kind == "trap":
		p.stunned_until = host.gifts.now() + roundi(duration * 1000.0)
		travel(pid, World.move(p.pos, Vector2(0, 38)))
	host._to(pid, "c_adventure_control", [kind == "trap", duration])


## Выполняет управляемый сервером переход.
func travel(pid: int, point: Vector2) -> void:
	var p: Dictionary = host.players[pid]
	p.pos = Sites.open_point(World, point)
	p.moved_at = host.gifts.now()
	p.forced_from_until = p.moved_at + 250
	host._to(pid, "c_teleport", [p.pos, true])


## Считает непрерывный бег по принятым хостом позициям.
func movement(p: Dictionary, position: Vector2) -> void:
	if not host.gifts.has(p, "run_charge"):
		return
	var time: int = host.gifts.now()
	var gap := time - int(p.get("run_sample", time))
	p.run_sample = time
	if gap <= 0:
		return
	var rate: float = p.pos.distance_to(position) * 1000.0 / gap
	if gap <= 300 and rate >= 85.0:
		p.run_ms = mini(5000, int(p.get("run_ms", 0)) + gap)
		if p.run_ms >= 5000:
			p.run_charged = true
	else:
		p.run_ms = 0


## Разряжает накопленный бег первым попаданием.
func hit(pid: int, eid: int, e: Dictionary, damage: int) -> void:
	var p: Dictionary = host.players[pid]
	e.last_attacker = pid
	e.attacked_by = e.get_or_add("attacked_by", {})
	e.attacked_by[pid] = true
	if p.get("run_charged", false):
		p.run_charged = false
		p.run_ms = 0
		host._all("c_shot", [p.pos, e.pos, "arcane", 0.0])
		host.gifts.deal(pid, eid, maxi(1, roundi(damage * 0.5)))


## Призывает метеор при первом подходящем применении после перезарядки.
func skill(pid: int, dir: Vector2) -> void:
	var p: Dictionary = host.players[pid]
	var time: int = host.gifts.now()
	if not host.gifts.has(p, "meteor") or time < int(p.get("gift_meteor_at", 0)):
		return
	p.gift_meteor_at = time + 60000
	var point: Vector2 = p.pos + dir * 70.0
	host._all("c_world_pulse", [point, 65.0, Color.ORANGE_RED])
	for eid in host.gifts.nearby(point, 65.0):
		host.gifts.deal(pid, eid, maxi(1, roundi(Rules.damage(p) * 1.5)))


## Учитывает привыкание к одному виду врагов при получении урона.
func resistance(pid: int, kind: String) -> float:
	var p: Dictionary = host.players[pid]
	if kind == "" or not host.gifts.has(p, "adapt"):
		return 1.0
	var stacks: Dictionary = p.get_or_add("adapt", {})
	var count := int(stacks.get(kind, 0))
	stacks[kind] = mini(15, count + 1)
	return 1.0 - count * 0.02


## Передаёт часть урона связанному союзнику и обрабатывает спасение.
func intervene(pid: int, incoming: int) -> int:
	var p: Dictionary = host.players[pid]
	for other in allies(pid):
		var ally: Dictionary = host.players[other]
		if host.gifts.has(ally, "share_dmg30"):
			var transferred := mini(incoming, roundi(incoming * 0.30))
			incoming -= transferred
			ally.hp = maxi(0, int(ally.hp) - transferred)
			ally.hurt_at = host.gifts.now()
			host.gifts.health_events(other, {"damage": transferred})
			host._all("c_hp", [other, ally.hp, ally.max_hp, transferred])
			if ally.hp == 0:
				ally.dead_t = host.RESPAWN_TIME
			break
	if incoming >= p.hp:
		for other in allies(pid):
			var ally: Dictionary = host.players[other]
			if host.gifts.has(ally, "ally_cheat_death") and host.gifts.now() >= int(ally.get("gift_angel_at", 0)):
				ally.gift_angel_at = host.gifts.now() + 180000
				return int(p.hp) - 1
	return incoming


## Награда убийства и постоянный прогресс пожирателя.
func killed(pid: int, enemy: Dictionary, ctx: Dictionary) -> void:
	var p: Dictionary = host.players[pid]
	if enemy.kind == "golem":
		if host.gifts.has(p, "boss_aggro_loot"):
			ctx.extra_drops = roundi(Items.BOSS_DROPS * 0.5)
		if host.gifts.has(p, "devourer"):
			p.gift_state.devourer = int(p.gift_state.get("devourer", 0)) + 1
			host._send_self(pid)


## Воскрешение на месте, штраф смерти и усиление короля.
func death(pid: int) -> void:
	var p: Dictionary = host.players[pid]
	if Sites.CAVE.has_point(p.pos) and host.gifts.has(p, "dungeon_revive") and not p.get("gift_dungeon_revived", false):
		p.gift_dungeon_revived = true
		revive(pid)
		return
	var penalty := 0.15 if host.gifts.has(p, "death_penalty3") else 0.05
	p.coins -= floori(p.coins * penalty)
	host._send_self(pid)
	for other in host.players:
		var ally: Dictionary = host.players[other]
		if other != pid and ally.hp > 0 and host.gifts.has(ally, "king"):
			host.gifts.buff(ally, "royal_rage", 0.40, 10.0)


## Лечение поднимает ближайшего павшего при готовности дара.
func phoenix(pid: int, radius: float) -> void:
	var p: Dictionary = host.players[pid]
	if not host.gifts.has(p, "revive_heal") or host.gifts.now() < int(p.get("gift_phoenix_at", 0)):
		return
	var best := radius
	var found := -1
	for other in host.players:
		var ally: Dictionary = host.players[other]
		if ally.hp <= 0 and p.pos.distance_to(ally.pos) <= best:
			best = p.pos.distance_to(ally.pos)
			found = other
	if found != -1:
		p.gift_phoenix_at = host.gifts.now() + 600000
		revive(found)


## Воскрешает союзника на месте.
func revive(pid: int) -> void:
	var p: Dictionary = host.players[pid]
	p.hp = maxi(1, roundi(p.max_hp * 0.40))
	p.gift_low = false
	p.gift_critical = false
	p.invuln_until = host.gifts.now() + (10000 if host.gifts.has(p, "respawn_shield") else 1500)
	host._all("c_hp", [pid, p.hp, p.max_hp, 0])


## Начинает помощь ближайшему павшему союзнику.
func begin_revive(pid: int) -> void:
	var p: Dictionary = host.players[pid]
	for other in host.players:
		var ally: Dictionary = host.players[other]
		if ally.hp <= 0 and p.pos.distance_to(ally.pos) < 65.0 and not p.has("work") and not p.has("rescue"):
			p.rescue = {"pid": other, "started": host.gifts.now(), "until": host.gifts.now() + roundi(4000.0 / maxf(0.1, host.gifts.factor(pid, "revive_speed")))}
			host._to(pid, "c_announce", ["Вы поднимаете союзника.", Color.WHEAT])
			return


## Проверяет дистанцию до союзника до окончания подъёма.
func update_revive(pid: int) -> void:
	var p: Dictionary = host.players[pid]
	var rescue: Dictionary = p.get("rescue", {})
	if rescue.is_empty():
		return
	var ally: Dictionary = host.players.get(rescue.pid, {})
	if p.hp <= 0 or ally.is_empty() or ally.hp > 0 or p.pos.distance_to(ally.pos) >= 65.0 or int(p.get("hurt_at", 0)) > int(rescue.started):
		p.erase("rescue")
	elif int(rescue.until) <= host.gifts.now():
		revive(rescue.pid)
		p.erase("rescue")


## Волк от прока, приручённый зверь или постоянный спутник.
func companion_tick(pid: int, time: int) -> void:
	var p: Dictionary = host.players[pid]
	var permanent: bool = host.gifts.has(p, "pet_companion") or (host.gifts.has(p, "tame") and p.gift_state.get("pet", false))
	if not permanent and time >= int(p.get("gift_wolf_until", 0)):
		if p.erase("gift_pet_pos"):
			host._all("c_adventure_mark", ["pet_%d" % pid, Vector2.ZERO, false])
		return
	var pos: Vector2 = p.pos + Vector2(14, 12)
	for eid in host.gifts.nearby(p.pos, 100.0):
		pos = host.enemies[eid].pos + Vector2(12, 10)
		var damage := 3 + int(p.level * 0.7) if permanent else maxi(2, roundi(Rules.damage(p) * 0.35))
		host.gifts.deal(pid, eid, damage)
		break
	p.gift_pet_pos = pos
	host._all("c_adventure_mark", ["pet_%d" % pid, pos, true])


## Обрабатывает запрошенные действия даров и подъём союзника.
func action(pid: int, op: String, arg: String) -> void:
	var p: Dictionary = host.players[pid]
	var time: int = host.gifts.now()
	match op:
		"rescue": begin_revive(pid)
		"recall":
			if host.gifts.has(p, "recall300") and Sites.CAMPS.has(arg) and p.visited.has(arg) and time >= int(p.get("gift_recall_at", 0)):
				p.gift_recall_at = time + 300000
				travel(pid, Sites.CAMPS[arg])
		"time_stop":
			if host.gifts.has(p, "time_stop") and time >= int(p.get("gift_time_at", 0)):
				p.gift_time_at = time + 120000
				host._all("c_world_pulse", [p.pos, 150.0, Color.MEDIUM_PURPLE])
				for eid in host.gifts.nearby(p.pos, 150.0):
					var e: Dictionary = host.enemies[eid]
					e.slow_factor = 0.5
					e.slow_until = maxi(int(e.get("slow_until", 0)), time + (750 if e.kind == "golem" else 3000))
		"copy":
			if host.gifts.has(p, "copy_gift") and time >= int(p.get("gift_copy_at", 0)):
				var nearest := -1
				var distance := 200.0
				for other in allies(pid, 200.0):
					var dist: float = host.players[other].pos.distance_to(p.pos)
					if dist < distance:
						nearest = other
						distance = dist
				if nearest != -1:
					for id in Gifts.ids(host.players[nearest]):
						if id not in Gifts.ids(p) and Gifts.get_gift(id).get("flag") != "copy_gift":
							p.get_or_add("temp_gifts", {})[id] = time + 600000
							p.gift_copy_at = time + 600000
							host._to(pid, "c_announce", ["Скопирован дар: %s" % Gifts.get_gift(id).name, Color.MEDIUM_PURPLE])
							break
		"cross":
			if host.gifts.has(p, "cross_skill") and Sites.is_safe(World, p.pos) and Rules.SKILLS.has(arg) and arg not in Rules.class_of(p).skills:
				p.cross_skill = arg
		"tame":
			if host.gifts.has(p, "tame"):
				for eid in host.gifts.nearby(p.pos, 56.0):
					var e: Dictionary = host.enemies[eid]
					if e.kind == "wolf" and host.gifts.ratio(e) < 0.35:
						p.gift_state.pet = true
						host.enemies.erase(eid)
						host._all("c_enemy_died", [eid])
						break
	host._send_self(pid)
