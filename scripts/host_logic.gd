extends Node
## Логика мира, которая работает только у хоста: враги, бой, лут, инвентари, обмены.
## Клиентам доверяется только позиция (это кооп), всё ценное проверяется здесь.

const Sites := preload("res://scripts/adventure_sites.gd")
const RESPAWN_TIME := 8.0
const BOSS_RESPAWN := 120.0
const ZONE_CAP := {"slime": 8, "wolf": 7, "undead": 4}

var game                     # game.gd
var players := {}            # peer_id -> {name, pos, facing, hp, max_hp, inv, equip, gold, trade, invite, ...}
var enemies := {}            # eid -> {kind, pos, hp, max_hp, cd, wander, wander_t}
var loots := {}              # lid -> {item, pos}
var trader
var next_id := 0
var serial := 0
var boss_timer := 45.0
var regen_acc := 0.0
var net_acc := 0.0
var eco                      # host_economy.gd
var gifts
var talents
var professions
var enemy_gift_ai
var skills                   # host_skills.gd


func _ready() -> void:
	skills = preload("res://scripts/host_skills.gd").new()
	skills.host = self
	add_child(skills)
	gifts = preload("res://scripts/host_gifts.gd").new()
	gifts.host = self
	add_child(gifts)
	talents = preload("res://scripts/host_talents.gd").new()
	talents.host = self
	professions = preload("res://scripts/host_professions.gd").new()
	professions.host = self
	professions.setup()
	enemy_gift_ai = preload("res://scripts/enemy_gift_ai.gd").new()
	enemy_gift_ai.host = self
	trader = preload("res://scripts/host_trade.gd").new()
	trader.host = self


func start_world() -> void:
	eco = preload("res://scripts/host_economy.gd").new()
	eco.host = self
	add_child(eco)
	serial = int(Save.load_world().get("serial", 0))
	for i in 6:
		spawn_enemy("slime")
	for i in 5:
		spawn_enemy("wolf")
	for i in 3:
		spawn_enemy("undead")


# ---------- утилиты ----------

func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return game.my_id if s == 0 else s


func _to(pid: int, method: StringName, args: Array = []) -> void:
	if pid == game.my_id:
		game.callv(method, args)
	elif multiplayer.get_peers().has(pid):
		game.callv("rpc_id", [pid, method] + args)


func _all(method: StringName, args: Array = []) -> void:
	for pid in players.keys():
		_to(pid, method, args)


func _nid() -> int:
	next_id += 1
	return next_id


func _public(pid: int) -> Dictionary:
	var p: Dictionary = players[pid]
	return {"id": pid, "name": p.name, "pos": p.pos, "equip": p.equip.duplicate(true), "look": p.look,
		"hp": p.hp, "max_hp": p.max_hp, "cls": p.cls, "gifts": p.gifts.duplicate()}


func _private(pid: int) -> Dictionary:
	var p: Dictionary = players[pid]
	return {"inv": p.inv.duplicate(true), "equip": p.equip.duplicate(true), "coins": p.coins, "look": p.look,
		"bank": p.bank.duplicate(true), "bounties": p.bounties.duplicate(),
		"materials": p.materials.duplicate(), "professions": p.professions.duplicate(), "tools": p.tools.duplicate(),
		"visited": p.visited.duplicate(), "temp_gifts": p.get("temp_gifts", {}).duplicate(), "cross_skill": p.cross_skill,
		"hp": p.hp, "max_hp": p.max_hp, "pos": p.pos, "level": p.level, "xp": p.xp, "points": p.points,
		"stats": p.stats.duplicate(), "cds": skills.cds_left(p), "buffs": skills.buffs_left(p),
		"cls": p.cls, "gifts": p.gifts.duplicate(), "res": int(p.res), "res_max": int(p.res_max), "gift_state": p.gift_state.duplicate(), "shield": int(p.get("shield", 0)),
		"gift_motion": p.get("gift_motion", {}).duplicate(), "gift_buff_power": p.get("gift_buff_power", {}).duplicate(), "gift_speed": gifts.buff_value(p, "speed"), "gift_aspd": gifts.buff_value(p, "aspd")}


func _find(inv: Array, uid: String) -> int:
	for i in inv.size():
		if inv[i].uid == uid:
			return i
	return -1


func _send_self(pid: int) -> void:
	_to(pid, "c_self", [_private(pid)])


# ---------- игроки ----------

func register(data: Dictionary) -> void:
	var id := _sender()
	if players.has(id):
		return
	var p := Save.sanitize_char(data)
	p.merge({"pos": game.SPAWN + Vector2(randf_range(-30, 30), randf_range(-10, 20)),
		"facing": Vector2.RIGHT, "trade": 0, "invite": -1, "cds": {}, "buffs": {}})
	p.peer_id = id
	p.gift_dash = preload("res://scripts/dash_charges.gd").new()
	p.moved_at = Time.get_ticks_msec()
	players[id] = p
	p.max_hp = Rules.max_hp(p, gifts.factor(id, "hp"))
	p.hp = p.max_hp
	skills.init_res(p)
	print("[host] игрок вошёл: %s (peer %d), предметов: %d" % [p.name, id, p.inv.size()])
	var ps := []
	for pid in players:
		ps.append(_public(pid))
	var es := []
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		es.append([eid, e.kind, e.pos, e.hp, e.max_hp, e.get("elite", false)])
	var ls := []
	for lid in loots:
		ls.append([lid, loots[lid].item, loots[lid].pos])
	_to(id, "c_init", [ps, es, ls, _private(id)])
	for mark in professions.carcasses:
		_to(id, "c_adventure_mark", [mark, professions.carcasses[mark].pos, true])
	for other in players:
		if other != id:
			_to(other, "c_player_joined", [_public(id)])
	_all("c_announce", ["%s входит в мир" % p.name, Color(0.7, 0.9, 1.0)])


func on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	var tid: int = players[id].trade
	if trader.trades.has(tid):
		trader.close_trade(tid, "Партнёр по обмену вышел из игры.")
	var pname: String = players[id].name
	players.erase(id)
	_all("c_adventure_mark", ["pet_%d" % id, Vector2.ZERO, false])
	_all("c_player_left", [id])
	_all("c_announce", ["%s покидает мир" % pname, game.GREY])


func update_pos(pos: Vector2, facing: Vector2) -> void:
	var p = players.get(_sender())
	if p == null or int(p.hp) <= 0:
		return
	if not pos.is_finite() or not facing.is_finite() or not can_act(p) or gifts.now() < int(p.get("forced_from_until", 0)):
		return
	if pos.distance_to(p.pos) > 120.0:
		return
	talents.movement(p, pos)
	if p.pos.distance_squared_to(pos) > 0.01:
		p.moved_at = Time.get_ticks_msec()
	p.pos = pos.clamp(Vector2(24, 24), game.WORLD_SIZE - Vector2(24, 24))
	p.facing = facing


func _process(delta: float) -> void:
	var me = players.get(game.my_id)
	if me and can_act(me):
		talents.movement(me, game.my_pos)
		if me.pos.distance_squared_to(game.my_pos) > 0.01:
			me.moved_at = Time.get_ticks_msec()
		me.pos = game.my_pos
		me.facing = game.my_facing
	_enemy_ai(delta)
	gifts.update()
	professions.update()
	_players_tick(delta)
	boss_timer -= delta
	if boss_timer <= 0.0:
		boss_timer = BOSS_RESPAWN
		if not _boss_alive():
			spawn_enemy("golem")
			_all("c_announce", ["⚠ Каменный Голем пробудился! Из него падает лучший лут.", Color(1, 0.5, 0.3)])
	for kind in ZONE_CAP:
		if _count(kind) < ZONE_CAP[kind] and randf() < delta * 0.25:
			spawn_enemy(kind)
	net_acc += delta
	if net_acc >= game.NET_TICK:
		net_acc = 0.0
		_broadcast_state()


func _players_tick(delta: float) -> void:
	regen_acc += delta
	var regen := regen_acc >= 1.0
	if regen:
		regen_acc = 0.0
	for pid in players:
		var p: Dictionary = players[pid]
		talents.update_revive(pid)
		if int(p.hp) <= 0:
			p.dead_t = float(p.get("dead_t", RESPAWN_TIME)) - delta
			if p.dead_t <= 0.0:
				p.hp = p.max_hp
				p.gift_low = false
				p.gift_critical = false
				if gifts.has(p, "respawn_shield"):
					p.invuln_until = gifts.now() + 10000
				p.pos = game.SPAWN
				_to(pid, "c_teleport", [game.SPAWN, false])
				_all("c_hp", [pid, p.hp, p.max_hp, 0])
		elif regen and p.hp < p.max_hp and Time.get_ticks_msec() - int(p.get("hurt_at", 0)) > 4000:
			p.gift_regen = float(p.get("gift_regen", 0.0)) + 4 * float(Rules.race_of(p).get("regen_mult", 1.0)) * gifts.factor(pid, "hp_regen") * (2.0 - gifts.ratio(p) if gifts.has(p, "hydra") else 1.0)
			var amount := int(p.gift_regen)
			p.gift_regen -= amount
			p.hp = mini(p.max_hp, p.hp + amount)
			_all("c_hp", [pid, p.hp, p.max_hp, 0])
	skills.res_tick(delta)


func dash(dir: Vector2) -> void:
	var id := _sender()
	var p = players.get(id)
	if not can_act(p) or not dir.is_finite() or dir.is_zero_approx():
		return
	if not p.gift_dash.consume(p, skills.has_buff(p, "pounce")):
		return
	p.invuln_until = maxi(int(p.get("invuln_until", 0)), Time.get_ticks_msec() + 260)
	var from: Vector2 = p.pos
	var end := World.move(from, dir.normalized() * game.SPEED * game.DASH_SPEED * 0.2 * Rules.Gifts.factor(p, "dash_dist"))
	if gifts.has(p, "blink_dash"):
		talents.travel(id, end)
	_all("c_dash", [id])
	if gifts.has(p, "dash_reset_hit"):
		for eid in gifts.nearby(from, from.distance_to(end) + 22.0):
			var point: Vector2 = enemies[eid].pos
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, end)) <= 22.0:
				gifts.deal(id, eid, maxi(1, roundi(Rules.damage(p) * 0.30)))
				p.gift_dash.used.clear()
				_to(id, "c_dash_reset")
				break
	gifts.fire(id, "dash", {"from": from, "end": end})


## Парирование: открывает окно, в которое удар врага полностью гасится (см. _hurt_player).
func parry() -> void:
	var id := _sender()
	var p = players.get(id)
	if not can_act(p) or not Rules.can_parry(p):
		return
	var now := Time.get_ticks_msec()
	if now < int(p.get("parry_ready", 0)):
		return
	p.parry_ready = now + int(Rules.PARRY.cd * 1000.0)
	p.parry_until = now + int(Rules.PARRY.window * gifts.factor(id, "parry_window") * 1000.0)
	_all("c_parry", [id])


## Удар врага eid по игроку. Броня режет урон, но не ниже Rules.ENEMY_MIN_DMG от удара —
## иначе толстая броня делает героя бессмертным, и враги перестают что-то значить.
func _hurt_player(pid: int, dmg: int, eid: int = -1, kind: String = "melee") -> void:
	var p: Dictionary = players[pid]
	var now := Time.get_ticks_msec()
	if p.hp <= 0 or now < int(p.get("invuln_until", 0)):
		return
	if kind == "melee" and eid >= 0 and now < int(p.get("parry_until", 0)) and enemies.has(eid):
		p.parry_until = 0
		p.parry_ready = now + 600                            # удачное парирование быстро готово снова
		p.erase("gift_riposte")
		p.riposte_until = now + int(Rules.PARRY.riposte_time * 1000.0)
		var e: Dictionary = enemies[eid]
		e.stun_until = now + int(Rules.PARRY.stun * (Rules.Gifts.BOSS_RULES.cc_mult if e.kind == "golem" else 1.0) * 1000.0)
		if Rules.res_kind(p) == "rage":
			skills.add_res(p, Rules.PARRY.rage)
		var ctx := {"eid": eid, "enemy": e, "damage": dmg}
		gifts.combat(pid, ctx)
		gifts.fire(pid, "parry", ctx)
		_all("c_parried", [pid, e.pos])
		if p.parry_ready == 0:
			_to(pid, "c_parry_reset")
		return
	var mult: float = skills.damage_taken_mult(p)
	if mult <= 0.0:
		return                                              # божественный щит
	var ctx := {"eid": eid, "enemy": enemies.get(eid, {}), "damage": dmg}
	gifts.combat(pid, ctx)
	var dodge := clampf(gifts.mod(pid, "dodge", ctx), 0.0, Rules.Gifts.CAPS.dodge)
	if randf() < dodge:
		gifts.fire(pid, "dodge", ctx)
		return
	if Rules.Gifts.has_flag(p, "block30") and now >= int(p.get("gift_block_at", 0)):
		p.gift_block_at = now + 30000
		return
	var floor_dmg := maxi(1, int(dmg * Rules.ENEMY_MIN_DMG))
	var armor := 0.0 if Rules.Gifts.has_flag(p, "no_armor") else (Rules._gear_sum(p, "armor") + int(Rules.race_of(p).get("armor", 0))) * float(gifts.factor(pid, "armor", ctx))
	mult = maxf(Rules.MIN_DMG_TAKEN, mult * gifts.factor(pid, "dmg_taken_" + kind, ctx) * talents.resistance(pid, str(ctx.enemy.get("kind", ""))))
	var dealt: int = gifts.protect(pid, maxi(floor_dmg, int((dmg - int(armor * 0.5)) * mult)), floor_dmg)
	dealt = talents.intervene(pid, dealt)
	skills.on_hurt(pid)
	ctx.damage = mini(int(p.hp), dealt)
	p.hp = maxi(0, int(p.hp) - dealt)
	p.hurt_at = now
	gifts.fire(pid, "hurt", ctx)
	gifts.health_events(pid, ctx)
	_all("c_hp", [pid, p.hp, p.max_hp, dealt])
	var thorns := clampf(gifts.mod(pid, "thorns", ctx), 0.0, Rules.Gifts.CAPS.thorns)
	gifts.deal(pid, eid, int(ctx.damage * thorns))
	if p.hp == 0:
		p.dead_t = RESPAWN_TIME
		_all("c_announce", ["%s пал в бою. Союзник может помочь клавишей R." % p.name, Color(1, 0.4, 0.4)])


func _broadcast_state() -> void:
	var ps := []
	for pid in players:
		ps.append([pid, players[pid].pos, players[pid].facing])
	var es := []
	for eid in enemies:
		es.append([eid, enemies[eid].pos, enemies[eid].hp])
	for pid in players:
		if pid != game.my_id and multiplayer.get_peers().has(pid):
			game.rpc_id(pid, "c_state", ps, es)
	game.c_state(ps, es)


# ---------- враги и бой ----------

func _count(kind: String) -> int:
	var n := 0
	for e in enemies.values():
		if e.kind == kind:
			n += 1
	return n


func _boss_alive() -> bool:
	for e in enemies.values():
		if e.kind == "golem":
			return true
	return false


func spawn_enemy(kind: String) -> void:
	var k: Dictionary = Items.ENEMIES[kind]
	var pos := World.random_spawn(kind)
	if kind == "undead":
		pos = Sites.open_point(World, Sites.CAVE.position + Vector2(randf_range(100, 305), randf_range(26, 103)))
	var eid := _nid()
	enemies[eid] = {"id": eid, "kind": kind, "pos": pos, "hp": k.hp, "max_hp": k.hp, "cd": 0.0,
		"wander": Vector2.ZERO, "wander_t": 0.0}
	_all("c_enemy_spawn", [[eid, kind, pos, k.hp, k.hp]])


func _enemy_ai(delta: float) -> void:
	for eid in enemies.keys():
		if not enemies.has(eid):
			continue
		var e: Dictionary = enemies[eid]
		var k: Dictionary = Items.ENEMIES[e.kind]
		e.cd = maxf(0.0, e.cd - delta)
		if int(e.get("stun_until", 0)) > Time.get_ticks_msec():
			continue                                        # оглушён (парирование): стоит и не бьёт
		var target: int = enemy_gift_ai.target(e, k)
		if target != -1:
			enemy_gift_ai.engage(eid, target, k, delta)
		else:
			e.wander_t -= delta
			if e.wander_t <= 0.0:
				e.wander_t = randf_range(1.5, 4.0)
				e.wander = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
			_step(e, e.wander * k.speed * 0.35 * delta, k)


func _step(e: Dictionary, d: Vector2, k: Dictionary) -> void:
	var r: float = k.radius * 0.5
	var np := World.move(e.pos, d, r)
	if not Sites.is_safe(World, np, 24.0) and (e.kind == "undead") == Sites.CAVE.has_point(np):
		e.pos = np


func attack(dir: Vector2) -> void:
	var id := _sender()
	var p = players.get(id)
	if not can_act(p) or not dir.is_finite():
		return
	skills.basic_attack(id, dir)


func _kill(eid: int, killer: int) -> void:
	var e: Dictionary = enemies[eid]
	for p in players.values():
		p.get("gift_first", {}).erase(eid)
	enemies.erase(eid)
	_all("c_enemy_died", [eid])
	var boss: bool = e.kind == "golem"
	var cr: Array = Items.COIN_DROPS[e.kind]
	var ctx := {"eid": eid, "enemy": e, "coins": randi_range(cr[0], cr[1]), "coin_mult": 1.0}
	var drop_mods := {}
	var loot_mult := 1.0
	if players.has(killer):
		var p: Dictionary = players[killer]
		eco.on_kill(killer, e.kind)
		talents.killed(killer, e, ctx)
		if Rules.Gifts.has_flag(p, "kill_streak"):
			p.get_or_add("gift_kills", []).append(gifts.now())
		ctx.coin_mult = float(Rules.race_of(p).get("coin_mult", 1.0)) * gifts.factor(killer, "coin", ctx)
		gifts.fire(killer, "kill", ctx)
		loot_mult = gifts.factor(killer, "loot", ctx)
		for key in ["rare_find", "mega_rare", "mythic_find"]:
			drop_mods[key] = gifts.factor(killer, key, ctx) - 1.0
	skills.on_kill(killer, e.kind, e.pos, ctx)
	drop(Items.make_coins(maxi(1, int(ctx.coins * minf(1.0 + Rules.Gifts.CAPS.coin, ctx.coin_mult)))), e.pos + Vector2(randf_range(-12, 12), randf_range(-8, 8)))
	var drops := Items.BOSS_DROPS if boss else (1 if randf() < Items.MOB_DROP_CHANCE * loot_mult else 0)
	drops += int(ctx.get("extra_drops", 0)) + int(e.get("elite", false) and not boss)
	if e.kind == "wolf":
		professions.add_carcass(eid, e)
	var owner: Dictionary = players.get(killer, {})
	for i in drops:
		var shift := 0
		if gifts.has(owner, "rarity_gamble"):
			shift = int(owner.get("gift_rarity_shift", 1))
			owner.gift_rarity_shift = -shift
		var item_ctx := {"enemy": e, "item": Items.roll_drop(boss, drop_mods, shift)}
		gifts.fire(killer, "loot", item_ctx)
		drop(item_ctx.item, e.pos + Vector2(randf_range(-36, 36), randf_range(-36, 36)))
	if boss:
		_all("c_announce", ["Голем повержен! Лут лежит на земле.", Color(1, 0.8, 0.4)])


func drop(item: Dictionary, pos: Vector2) -> void:
	var lid := _nid()
	loots[lid] = {"item": item, "pos": pos}
	_all("c_loot", [lid, item, pos])


func debug_jackpot() -> void:
	var item := Items.make(Items.UNIQUE_BASES.pick_random(), 5, "", randf() < 0.5)
	drop(item, game.my_pos + game.my_facing * 70.0)


# ---------- инвентарь ----------

func pickup(lid: int) -> void:
	var id := _sender()
	var p = players.get(id)
	var l = loots.get(lid)
	if p == null or l == null or int(p.hp) <= 0:
		return
	if p.pos.distance_to(l.pos) > 70.0 * gifts.factor(id, "pickup"):
		return
	var item: Dictionary = l.item
	if item.base != "coins" and p.inv.size() >= Items.bag_capacity(p) and not Items.is_stack(item):
		return
	loots.erase(lid)
	item.finder = p.name
	if Items.is_jackpot(item):
		serial += 1
		item.serial = serial
		Save.store_world({"serial": serial})
	if not eco.add_item(p, item):
		loots[lid] = l                     # не влезло — остаётся лежать
		return
	_all("c_loot_gone", [lid])
	_send_self(id)
	if Items.is_jackpot(item):
		_all("c_jackpot", [p.name, item])
	elif int(item.rarity) >= 2:
		_all("c_announce", ["%s подобрал: %s [%s]" % [p.name, Items.display_name(item),
			Items.RARITY_NAMES[int(item.rarity)]], Items.color(item)])


func equip(uid: String) -> void:
	var id := _sender()
	var p = players.get(id)
	if p == null or int(p.trade) != 0:
		return
	var idx := _find(p.inv, uid)
	if idx < 0:
		return
	var item: Dictionary = p.inv[idx]
	var slot := Items.slot_of(item)
	if slot not in Items.SLOTS:
		return
	if slot == "offhand" and Rules.two_handed(p.equip.get("weapon", {})) and not gifts.has(p, "titan_grip"):
		_to(id, "c_announce", ["Щит нельзя надеть вместе с двуручным оружием.", Color.ORANGE])
		return
	if slot == "weapon" and Rules.two_handed(item) and p.equip.has("offhand") and not gifts.has(p, "titan_grip"):
		_to(id, "c_announce", ["Снимите щит перед сменой оружия.", Color.ORANGE])
		return
	p.inv.remove_at(idx)
	if p.equip.has(slot):
		p.inv.append(p.equip[slot])
	p.equip[slot] = item
	_after_equip(id)


func unequip(slot: String) -> void:
	var id := _sender()
	var p = players.get(id)
	if p == null or int(p.trade) != 0 or not p.equip.has(slot) or p.inv.size() >= Items.bag_capacity(p):
		return
	p.inv.append(p.equip[slot])
	p.equip.erase(slot)
	_after_equip(id)


func _after_equip(id: int) -> void:
	_send_self(id)
	_all("c_equip", [id, players[id].equip.duplicate(true)])


func chat(text: String) -> void:
	var id := _sender()
	if not players.has(id):
		return
	var t := text.strip_edges().left(120)
	if t != "":
		_all("c_chat", [players[id].name, t])


## Проверяет, может ли герой действовать.
func can_act(p) -> bool:
	return p != null and int(p.hp) > 0 and Time.get_ticks_msec() >= int(p.get("stunned_until", 0))


## Принимает запрос на действие в мире.
func adventure(op: String, arg: String) -> void:
	var pid := _sender()
	var p = players.get(pid)
	if not can_act(p) or int(p.trade) != 0:
		return
	if op in ["rescue", "recall", "time_stop", "copy", "cross", "tame"]:
		talents.action(pid, op, arg)
	else:
		professions.handle(pid, op, arg)
