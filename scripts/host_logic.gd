extends Node
## Логика мира, которая работает только у хоста: враги, бой, лут, инвентари, обмены.
## Клиентам доверяется только позиция (это кооп), всё ценное проверяется здесь.

const BOSS_RESPAWN := 120.0
const ZONE_CAP := {"slime": 8, "wolf": 7}
const MAX_OFFER := 8

var game                     # game.gd
var players := {}            # peer_id -> {name, pos, facing, hp, max_hp, inv, equip, gold, trade, invite, ...}
var enemies := {}            # eid -> {kind, pos, hp, max_hp, cd, wander, wander_t}
var loots := {}              # lid -> {item, pos}
var trades := {}             # tid -> {a, b, offer: {id: [uid]}, ok: {id: bool}}
var next_id := 0
var serial := 0
var boss_timer := 45.0
var regen_acc := 0.0
var net_acc := 0.0
var eco                      # host_economy.gd
var skills                   # host_skills.gd


func _ready() -> void:
	skills = preload("res://scripts/host_skills.gd").new()
	skills.host = self
	add_child(skills)


func start_world() -> void:
	eco = preload("res://scripts/host_economy.gd").new()
	eco.host = self
	add_child(eco)
	serial = int(Save.load_world().get("serial", 0))
	for i in 6:
		spawn_enemy("slime")
	for i in 5:
		spawn_enemy("wolf")


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
		"hp": p.hp, "max_hp": p.max_hp, "pos": p.pos, "level": p.level, "xp": p.xp, "points": p.points,
		"stats": p.stats.duplicate(), "cds": skills.cds_left(p), "buffs": skills.buffs_left(p),
		"cls": p.cls, "gifts": p.gifts.duplicate(), "res": int(p.res), "res_max": int(p.res_max)}


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
	p.max_hp = Rules.max_hp(p)
	p.hp = p.max_hp
	skills.init_res(p)
	players[id] = p
	print("[host] игрок вошёл: %s (peer %d), предметов: %d" % [p.name, id, p.inv.size()])
	var ps := []
	for pid in players:
		ps.append(_public(pid))
	var es := []
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		es.append([eid, e.kind, e.pos, e.hp, e.max_hp])
	var ls := []
	for lid in loots:
		ls.append([lid, loots[lid].item, loots[lid].pos])
	_to(id, "c_init", [ps, es, ls, _private(id)])
	for other in players:
		if other != id:
			_to(other, "c_player_joined", [_public(id)])
	_all("c_announce", ["%s входит в мир" % p.name, Color(0.7, 0.9, 1.0)])


func on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	var tid: int = players[id].trade
	if trades.has(tid):
		close_trade(tid, "Партнёр по обмену вышел из игры.")
	var pname: String = players[id].name
	players.erase(id)
	_all("c_player_left", [id])
	_all("c_announce", ["%s покидает мир" % pname, game.GREY])


func update_pos(pos: Vector2, facing: Vector2) -> void:
	var p = players.get(_sender())
	if p == null or int(p.hp) <= 0:
		return
	if pos.distance_to(p.pos) > 120.0:   # грубая защита от телепорта
		return
	p.pos = pos.clamp(Vector2(24, 24), game.WORLD_SIZE - Vector2(24, 24))
	p.facing = facing


func _process(delta: float) -> void:
	var me = players.get(game.my_id)
	if me and int(me.hp) > 0:
		me.pos = game.my_pos
		me.facing = game.my_facing
	_enemy_ai(delta)
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
		if int(p.hp) <= 0:
			p.dead_t = float(p.get("dead_t", 3.0)) - delta
			if p.dead_t <= 0.0:
				p.hp = p.max_hp
				p.pos = game.SPAWN
				_to(pid, "c_teleport", [game.SPAWN])
				_all("c_hp", [pid, p.hp, p.max_hp, 0])
		elif regen and p.hp < p.max_hp and Time.get_ticks_msec() - int(p.get("hurt_at", 0)) > 4000:
			p.hp = mini(p.max_hp, p.hp + int(4 * float(Rules.race_of(p).get("regen_mult", 1.0))))
			_all("c_hp", [pid, p.hp, p.max_hp, 0])
	skills.res_tick(delta)


func dash() -> void:
	var id := _sender()
	if players.has(id):
		players[id].invuln_until = Time.get_ticks_msec() + 260      # рывок даёт неуязвимость
		_all("c_dash", [id])


func _hurt_player(pid: int, dmg: int) -> void:
	var p: Dictionary = players[pid]
	if Time.get_ticks_msec() < int(p.get("invuln_until", 0)):
		return
	var mult: float = skills.damage_taken_mult(p)
	if mult <= 0.0:
		return                                              # божественный щит
	var dealt := maxi(1, int((dmg - int(Rules.armor(p) * 0.5)) * mult))
	skills.on_hurt(pid)
	p.hp = maxi(0, int(p.hp) - dealt)
	p.hurt_at = Time.get_ticks_msec()
	_all("c_hp", [pid, p.hp, p.max_hp, dealt])
	if p.hp == 0:
		p.dead_t = 3.0
		_all("c_announce", ["%s пал в бою и вернётся через 3 сек." % p.name, Color(1, 0.4, 0.4)])


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
	var eid := _nid()
	enemies[eid] = {"kind": kind, "pos": pos, "hp": k.hp, "max_hp": k.hp, "cd": 0.0,
		"wander": Vector2.ZERO, "wander_t": 0.0}
	_all("c_enemy_spawn", [[eid, kind, pos, k.hp, k.hp]])


func _enemy_ai(delta: float) -> void:
	for eid in enemies:
		var e: Dictionary = enemies[eid]
		var k: Dictionary = Items.ENEMIES[e.kind]
		e.cd = maxf(0.0, e.cd - delta)
		var target := -1
		var best: float = k.aggro
		for pid in players:
			if int(players[pid].hp) <= 0 or World.in_town(players[pid].pos, 0.0):
				continue    # в городе безопасно
			var d: float = e.pos.distance_to(players[pid].pos)
			if d < best:
				best = d
				target = pid
		if target != -1:
			var slow := 0.5 if int(e.get("slow_until", 0)) > Time.get_ticks_msec() else 1.0
			if best > k.radius + 16.0:
				_step(e, (players[target].pos - e.pos).normalized() * k.speed * slow * delta, k)
			elif e.cd <= 0.0:
				e.cd = k.cooldown
				_hurt_player(target, k.dmg)
		else:
			e.wander_t -= delta
			if e.wander_t <= 0.0:
				e.wander_t = randf_range(1.5, 4.0)
				e.wander = Vector2.from_angle(randf() * TAU) if randf() < 0.6 else Vector2.ZERO
			_step(e, e.wander * k.speed * 0.35 * delta, k)


func _step(e: Dictionary, d: Vector2, k: Dictionary) -> void:
	var r: float = k.radius * 0.5
	var np := World.move(e.pos, d, r)
	if not World.in_town(np):
		e.pos = np


func attack(dir: Vector2) -> void:
	var id := _sender()
	var p = players.get(id)
	if p == null or int(p.hp) <= 0:
		return
	skills.basic_attack(id, dir)


func _kill(eid: int, killer: int) -> void:
	var e: Dictionary = enemies[eid]
	enemies.erase(eid)
	_all("c_enemy_died", [eid])
	var boss: bool = e.kind == "golem"
	var coin_mult := 1.0
	if players.has(killer):
		eco.on_kill(killer, e.kind)
		coin_mult = float(Rules.race_of(players[killer]).get("coin_mult", 1.0))
	skills.on_kill(killer, e.kind, e.pos)
	var cr: Array = Items.COIN_DROPS[e.kind]
	drop(Items.make_coins(int(randi_range(cr[0], cr[1]) * coin_mult)), e.pos + Vector2(randf_range(-12, 12), randf_range(-8, 8)))
	var drops := Items.BOSS_DROPS if boss else (1 if randf() < Items.MOB_DROP_CHANCE else 0)
	for i in drops:
		drop(Items.roll_drop(boss), e.pos + Vector2(randf_range(-36, 36), randf_range(-36, 36)))
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
	if p.pos.distance_to(l.pos) > 70.0:
		return
	var item: Dictionary = l.item
	if item.base != "coins" and p.inv.size() >= Items.MAX_INV and not Items.is_stack(item):
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
	p.inv.remove_at(idx)
	if p.equip.has(slot):
		p.inv.append(p.equip[slot])
	p.equip[slot] = item
	_after_equip(id)


func unequip(slot: String) -> void:
	var id := _sender()
	var p = players.get(id)
	if p == null or int(p.trade) != 0 or not p.equip.has(slot) or p.inv.size() >= Items.MAX_INV:
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


# ---------- обмен ----------

func trade_request(target: int) -> void:
	var id := _sender()
	if id == target or not players.has(id) or not players.has(target):
		return
	if int(players[id].trade) != 0 or int(players[target].trade) != 0:
		_to(id, "c_announce", ["Этот игрок сейчас занят другим обменом.", game.GREY])
		return
	if players[id].pos.distance_to(players[target].pos) > game.TRADE_RANGE:
		_to(id, "c_announce", ["Подойди ближе, чтобы обменяться.", game.GREY])
		return
	players[target].invite = id
	_to(target, "c_trade_invite", [id, players[id].name])
	_to(id, "c_announce", ["Предложение обмена отправлено: %s" % players[target].name, game.GREY])


func trade_answer(from: int, accept: bool) -> void:
	var id := _sender()
	if not players.has(id) or int(players[id].invite) != from or not players.has(from):
		return
	players[id].invite = -1
	if not accept:
		_to(from, "c_announce", ["%s отказался от обмена." % players[id].name, game.GREY])
		return
	if int(players[id].trade) != 0 or int(players[from].trade) != 0:
		return
	var tid := _nid()
	trades[tid] = {"a": from, "b": id, "offer": {from: [], id: []}, "ok": {from: false, id: false}}
	players[from].trade = tid
	players[id].trade = tid
	_to(from, "c_trade_open", [players[id].name])
	_to(id, "c_trade_open", [players[from].name])
	_push_trade(tid)


func _my_trade(id: int):
	if not players.has(id):
		return null
	return trades.get(int(players[id].trade))


func trade_offer(uids: Array) -> void:
	var id := _sender()
	var t = _my_trade(id)
	if t == null:
		return
	var valid := []
	for u in uids:
		if u is String and not valid.has(u) and valid.size() < MAX_OFFER and _find(players[id].inv, u) >= 0:
			valid.append(u)
	t.offer[id] = valid
	for k in t.ok:
		t.ok[k] = false      # любое изменение сбрасывает подтверждения — защита от подмены
	_push_trade(players[id].trade)


func trade_confirm() -> void:
	var id := _sender()
	var t = _my_trade(id)
	if t == null:
		return
	t.ok[id] = true
	if t.ok[t.a] and t.ok[t.b]:
		_execute_trade(players[id].trade)
	else:
		_push_trade(players[id].trade)


func trade_cancel() -> void:
	var id := _sender()
	if _my_trade(id) != null:
		close_trade(players[id].trade, "Обмен отменён.")


func _items_of(pid: int, uids: Array) -> Array:
	var out := []
	for u in uids:
		var i := _find(players[pid].inv, u)
		if i >= 0:
			out.append(players[pid].inv[i])
	return out


func _push_trade(tid: int) -> void:
	var t: Dictionary = trades[tid]
	for side in [t.a, t.b]:
		var other: int = t.b if side == t.a else t.a
		_to(side, "c_trade_state", [_items_of(side, t.offer[side]), _items_of(other, t.offer[other]),
			t.ok[side], t.ok[other]])


## Обмен происходит целиком или не происходит вообще.
func _execute_trade(tid: int) -> void:
	var t: Dictionary = trades[tid]
	var a: Dictionary = players[t.a]
	var b: Dictionary = players[t.b]
	var give_a := _items_of(t.a, t.offer[t.a])
	var give_b := _items_of(t.b, t.offer[t.b])
	if give_a.size() != t.offer[t.a].size() or give_b.size() != t.offer[t.b].size():
		close_trade(tid, "Обмен не удался: предметы изменились.")
		return
	if a.inv.size() - give_a.size() + give_b.size() > Items.MAX_INV \
			or b.inv.size() - give_b.size() + give_a.size() > Items.MAX_INV:
		close_trade(tid, "Обмен не удался: у кого-то не хватает места в сумке.")
		return
	for it in give_a:
		a.inv.remove_at(_find(a.inv, it.uid))
	for it in give_b:
		b.inv.remove_at(_find(b.inv, it.uid))
	a.inv.append_array(give_b)
	b.inv.append_array(give_a)
	close_trade(tid, "Обмен завершён!")


func close_trade(tid: int, msg: String) -> void:
	var t: Dictionary = trades[tid]
	trades.erase(tid)
	for side in [t.a, t.b]:
		if players.has(side):
			players[side].trade = 0
			_to(side, "c_trade_closed", [msg])
			_send_self(side)
