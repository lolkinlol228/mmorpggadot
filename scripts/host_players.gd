extends RefCounted
## Жизненный цикл героя, позиции, восстановление здоровья и ресурсов.

var host


func register(data: Dictionary) -> void:
	var id = host._sender()
	if host.players.has(id):
		return
	var p := Save.sanitize_char(data)
	for present in host.players.values():
		if present.name == p.name or present.hid == p.hid:
			host._to(id, "c_register_denied", ["Герой с таким именем уже в мире"])
			return
	if not host.market.claim_legacy(p):
		host._to(id, "c_register_denied", ["Не удалось сохранить владельца лотов. Попробуйте ещё раз."])
		return
	p.merge({"pos": host.game.SPAWN + Vector2(randf_range(-30, 30), randf_range(-10, 20)),
		"facing": Vector2.RIGHT, "trade": 0, "invite": -1, "cds": {}, "buffs": {}})
	p.peer_id = id
	p.gift_dash = preload("res://scripts/dash_charges.gd").new()
	p.moved_at = Time.get_ticks_msec()
	host.players[id] = p
	p.max_hp = Rules.max_hp(p, host.gifts.factor(id, "hp"))
	p.hp = p.max_hp
	host.skills.init_res(p)
	print("[host] игрок вошёл: %s (peer %d), предметов: %d" % [p.name, id, p.inv.size()])
	var ps := []
	for pid in host.players:
		ps.append(host._public(pid))
	var es := []
	for eid in host.enemies:
		var e: Dictionary = host.enemies[eid]
		es.append([eid, e.kind, e.pos, e.hp, e.max_hp, e.get("elite", false)])
	var ls := []
	for lid in host.loots:
		ls.append([lid, host.loots[lid].item, host.loots[lid].pos])
	host._to(id, "c_init", [ps, es, ls, host._private(id)])
	for mark in host.professions.carcasses:
		host._to(id, "c_adventure_mark", [mark, host.professions.carcasses[mark].pos, true])
	for other in host.players:
		if other != id:
			host._to(other, "c_player_joined", [host._public(id)])
	host._all("c_announce", ["%s входит в мир" % p.name, Color(0.7, 0.9, 1.0)])


func on_peer_disconnected(id: int) -> void:
	if not host.players.has(id):
		return
	var tid: int = host.players[id].trade
	if host.trader.trades.has(tid):
		host.trader.close_trade(tid, "Партнёр по обмену вышел из игры.")
	var pname: String = host.players[id].name
	host.players.erase(id)
	host._all("c_adventure_mark", ["pet_%d" % id, Vector2.ZERO, false])
	host._all("c_player_left", [id])
	host._all("c_announce", ["%s покидает мир" % pname, host.game.GREY])


func update_pos(pos: Vector2, facing: Vector2) -> void:
	var p = host.players.get(host._sender())
	if p == null or int(p.hp) <= 0:
		return
	if not pos.is_finite() or not facing.is_finite() or not host.can_act(p) or host.gifts.now() < int(p.get("forced_from_until", 0)):
		return
	if pos.distance_to(p.pos) > 120.0:
		return
	host.talents.movement(p, pos)
	if p.pos.distance_squared_to(pos) > 0.01:
		p.moved_at = Time.get_ticks_msec()
	p.pos = pos.clamp(Vector2(24, 24), host.game.WORLD_SIZE - Vector2(24, 24))
	p.facing = facing


func _players_tick(delta: float) -> void:
	host.regen_acc += delta
	var regen = host.regen_acc >= 1.0
	if regen:
		host.regen_acc = 0.0
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		host.talents.update_revive(pid)
		if int(p.hp) <= 0:
			p.dead_t = float(p.get("dead_t", host.RESPAWN_TIME)) - delta
			if p.dead_t <= 0.0:
				p.hp = p.max_hp
				p.gift_low = false
				p.gift_critical = false
				if host.gifts.has(p, "respawn_shield"):
					p.invuln_until = host.gifts.now() + 10000
				p.pos = host.game.SPAWN
				host._to(pid, "c_teleport", [host.game.SPAWN, false])
				host._all("c_hp", [pid, p.hp, p.max_hp, 0])
		elif regen and p.hp < p.max_hp and Time.get_ticks_msec() - int(p.get("hurt_at", 0)) > 4000:
			p.gift_regen = float(p.get("gift_regen", 0.0)) + 4 * float(Rules.race_of(p).get("regen_mult", 1.0)) * host.gifts.factor(pid, "hp_regen") * (2.0 - host.gifts.ratio(p) if host.gifts.has(p, "hydra") else 1.0)
			var amount := int(p.gift_regen)
			p.gift_regen -= amount
			p.hp = mini(p.max_hp, p.hp + amount)
			host._all("c_hp", [pid, p.hp, p.max_hp, 0])
	host.skills.res_tick(delta)


## Принимает локальную позицию героя хоста перед обновлением мира.
func sync_local() -> void:
	var me = host.players.get(host.game.my_id)
	if me and host.can_act(me):
		host.talents.movement(me, host.game.my_pos)
		if me.pos.distance_squared_to(host.game.my_pos) > 0.01:
			me.moved_at = Time.get_ticks_msec()
		me.pos = host.game.my_pos
		me.facing = host.game.my_facing
