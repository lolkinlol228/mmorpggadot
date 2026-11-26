extends RefCounted
## Создание врагов, ИИ, смерть и выдача добычи на хосте.

var host


func _count(kind: String) -> int:
	var n := 0
	for e in host.enemies.values():
		if e.kind == kind:
			n += 1
	return n


func _boss_alive() -> bool:
	for e in host.enemies.values():
		if e.kind == "golem":
			return true
	return false


func spawn_enemy(kind: String) -> void:
	var k: Dictionary = Items.ENEMIES[kind]
	var pos := World.random_spawn(kind)
	if kind == "undead":
		pos = host.Sites.open_point(World, host.Sites.CAVE.position + Vector2(randf_range(100, 305), randf_range(26, 103)))
	var eid = host._nid()
	host.enemies[eid] = {"id": eid, "kind": kind, "pos": pos, "hp": k.hp, "max_hp": k.hp, "cd": 0.0,
		"wander": Vector2.ZERO, "wander_t": 0.0}
	host._all("c_enemy_spawn", [[eid, kind, pos, k.hp, k.hp]])


func _enemy_ai(delta: float) -> void:
	for eid in host.enemies.keys():
		if not host.enemies.has(eid):
			continue
		var e: Dictionary = host.enemies[eid]
		var k: Dictionary = Items.ENEMIES[e.kind]
		e.cd = maxf(0.0, e.cd - delta)
		if int(e.get("stun_until", 0)) > Time.get_ticks_msec():
			continue                                        # оглушён (парирование): стоит и не бьёт
		var target: int = host.enemy_gift_ai.target(e, k)
		if target != -1:
			host.enemy_gift_ai.engage(eid, target, k, delta)
		else:
			e.wander_t -= delta
			if e.wander_t <= 0.0:
				e.wander_t = randf_range(1.5, 4.0)
				e.wander = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
			host._step(e, e.wander * k.speed * 0.35 * delta, k)


func _step(e: Dictionary, d: Vector2, k: Dictionary) -> void:
	var r: float = k.radius * 0.5
	var np := World.move(e.pos, d, r)
	if not host.Sites.is_safe(World, np, 24.0) and (e.kind == "undead") == host.Sites.CAVE.has_point(np):
		e.pos = np


func _kill(eid: int, killer: int) -> void:
	var e: Dictionary = host.enemies[eid]
	for p in host.players.values():
		p.get("gift_first", {}).erase(eid)
	host.enemies.erase(eid)
	host._all("c_enemy_died", [eid])
	var boss: bool = e.kind == "golem"
	var cr: Array = Items.COIN_DROPS[e.kind]
	var ctx := {"eid": eid, "enemy": e, "coins": randi_range(cr[0], cr[1]), "coin_mult": 1.0}
	var drop_mods := {}
	var loot_mult := 1.0
	if host.players.has(killer):
		var p: Dictionary = host.players[killer]
		host.eco.on_kill(killer, e.kind)
		host.talents.killed(killer, e, ctx)
		if Rules.Gifts.has_flag(p, "kill_streak"):
			p.get_or_add("gift_kills", []).append(host.gifts.now())
		ctx.coin_mult = float(Rules.race_of(p).get("coin_mult", 1.0)) * host.gifts.factor(killer, "coin", ctx)
		host.gifts.fire(killer, "kill", ctx)
		loot_mult = host.gifts.factor(killer, "loot", ctx)
		for key in ["rare_find", "mega_rare", "mythic_find"]:
			drop_mods[key] = host.gifts.factor(killer, key, ctx) - 1.0
		drop_mods.rare_find = minf(Rules.Gifts.CAPS.rare_find, float(drop_mods.rare_find) + Rules.luck_find(p))
	host.skills.on_kill(killer, e.kind, e.pos, ctx)
	host.drop(Items.make_coins(maxi(1, int(ctx.coins * minf(1.0 + Rules.Gifts.CAPS.coin, ctx.coin_mult)))), e.pos + Vector2(randf_range(-12, 12), randf_range(-8, 8)))
	var drops := Items.BOSS_DROPS if boss else (1 if randf() < Items.MOB_DROP_CHANCE * loot_mult else 0)
	drops += int(ctx.get("extra_drops", 0)) + int(e.get("elite", false) and not boss)
	if e.kind == "wolf":
		host.professions.add_carcass(eid, e)
	var owner: Dictionary = host.players.get(killer, {})
	for i in drops:
		var shift := 0
		if host.gifts.has(owner, "rarity_gamble"):
			shift = int(owner.get("gift_rarity_shift", 1))
			owner.gift_rarity_shift = -shift
		var item_ctx := {"enemy": e, "item": Items.roll_drop(boss, drop_mods, shift)}
		host.gifts.fire(killer, "loot", item_ctx)
		host.drop(item_ctx.item, e.pos + Vector2(randf_range(-36, 36), randf_range(-36, 36)))
	for trophy in preload("res://scripts/relics.gd").roll_trophies(e, loot_mult):   # трофеи для реликвий
		host.drop(trophy, e.pos + Vector2(randf_range(-20, 20), randf_range(-14, 14)))
	if boss:
		host._all("c_announce", ["Голем повержен! Лут лежит на земле.", Color(1, 0.8, 0.4)])
