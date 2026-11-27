extends RefCounted

const Sites := preload("res://scripts/adventure_sites.gd")
const Quest := preload("res://scripts/mine_quest.gd")
const POSTS := [
	["shell", Vector2(2760, 785)], ["ringer", Vector2(2955, 678)],
	["shell", Vector2(3090, 496)], ["ringer", Vector2(3145, 472)],
	["shell", Vector2(3188, 516)], ["warden", Vector2(3400, 300)]]
var host
var opened := false
var next_spawn := {}
var occupants := {}


func setup() -> void:
	opened = host.get_node("/root/Save").load_world().get("mine_open", false) == true


func open_mine() -> bool:
	if opened or not host.get_node("/root/Save").store_world({"mine_open": true}):
		return false
	opened = true
	host._all("c_announce", ["Вода у Пристани уходит… Расспросите Рыбака о проходе.", Color.AQUAMARINE])
	for pid in host.players:
		host._send_self(pid)
	return true


func tick() -> void:
	if not opened or occupants.size() == POSTS.size():
		return
	for p in host.players.values():
		if Sites.MINE.has_point(p.pos):
			return
	var now := Time.get_ticks_msec()
	for i in POSTS.size():
		if not occupants.has(i) and now >= int(next_spawn.get(i, 0)):
			var eid: int = host.host_enemies.spawn_at(POSTS[i][0], POSTS[i][1])
			host.enemies[eid].post = i
			occupants[i] = eid


func action(pid: int, op: String, arg: String) -> void:
	var p: Dictionary = host.players[pid]
	for spot in host.get_node("/root/World").zones.interact:
		if p.pos.distance_to(Vector2(spot.x, spot.y)) > 64.0:
			continue
		if op == "mine" and spot.kind == "mine" and arg == spot.action:
			if opened:
				host.talents.travel(pid, Sites.MINE_EXIT + Vector2(22, 0) if arg == "enter" else Sites.MINE_GATE + Vector2(0, 25))
			else:
				host._to(pid, "c_announce", ["Вход затоплен. Рыбак знает почему.", Color.SKY_BLUE])
			return
		if op == "talk" and opened and spot.get("actor") == arg:
			if (arg != "smith" or Quest.has_shard(p)) and Quest.progress(p.quests, arg):
				host._send_self(pid)
			return


func credit(event: String, pos: Vector2, actor: int) -> void:
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		if (pid == actor or (Sites.MINE.has_point(p.pos) and p.pos.distance_to(pos) <= host.get_node("/root/Rules").SHARE_XP_RADIUS)) and Quest.progress(p.quests, event):
			host._send_self(pid)


func killed(e: Dictionary, pid: int) -> void:
	if e.kind == "golem":
		open_mine()
	if e.has("post"):
		occupants.erase(e.post)
		next_spawn[e.post] = Time.get_ticks_msec() + (180000 if e.kind == "warden" else 30000)
	if e.kind in ["shell", "warden"]:
		credit(e.kind, e.pos, pid)


func interrupt(e: Dictionary, pid: int, now: int) -> void:
	if e.get("phase") != "ring":
		return
	e.phase = ""
	e.ring_at = now + 12000
	if e.kind == "ringer":
		credit("interrupt", e.pos, pid)


static func armor(e: Dictionary, from: Vector2, damage: int, now: int) -> int:
	if e.kind not in ["shell", "warden"]:
		return damage
	if now < int(e.get("open_until", 0)):
		return damage * 2
	var facing: Vector2 = e.get("facing", Vector2.LEFT)
	if facing.dot(e.pos.direction_to(from)) >= 0.55:
		return maxi(1, roundi(damage * 0.2))
	return damage


func damage(pid: int, e: Dictionary, amount: int, silence := false, wound := false) -> int:
	var now := Time.get_ticks_msec()
	if host.players.has(pid) and not wound:
		amount = armor(e, host.players[pid].pos, amount, now)
	if silence or amount >= float(e.max_hp) * 0.15:
		interrupt(e, pid, now)
	return amount


func brain(e: Dictionary, target: int, stats: Dictionary, delta: float, now: int) -> void:
	var phase: String = e.get("phase", "")
	if now < int(e.get("stun_until", 0)):
		interrupt(e, -1, now)
		e.phase = ""
		return
	if phase != "":
		if now < int(e.until):
			return
		e.phase = ""
		if phase == "ring":
			e.ring_at = now + 12000
			for side in [-1, 1]:
				var pt: Vector2 = e.pos + Vector2(22 * side, 15)
				var bounds := Sites.MINE.grow(-18)
				host.host_enemies.spawn_at("shell", pt.clamp(bounds.position, bounds.end))
		else:
			e.open_until = now + 1500
			e.cd = stats.cooldown
			for pid in host.players:
				var pos: Vector2 = host.players[pid].pos
				if e.pos.distance_to(pos) <= stats.radius + 26 and e.facing.dot(e.pos.direction_to(pos)) >= 0.35:
					host._hurt_player(pid, stats.dmg, e.id)
		return
	if target < 0 or now < int(e.get("open_until", 0)):
		return
	var player: Dictionary = host.players[target]
	var dir: Vector2 = e.pos.direction_to(player.pos)
	var dist: float = e.pos.distance_to(player.pos)
	var can_ring: bool = e.kind == "ringer" or (e.kind == "warden" and e.hp * 2 < e.max_hp)
	if can_ring and now >= int(e.get_or_add("ring_at", now + 12000)):
		e.phase = "ring"
		e.until = now + 3000
		return
	var speed := float(stats.speed) * (float(e.get("slow_factor", 1.0)) if now < int(e.get("slow_until", 0)) else 1.0)
	e.facing = dir
	if e.kind == "ringer":
		if dist < 65 or dist > 105:
			host._step(e, dir * speed * delta * (-1 if dist < 65 else 1), stats)
		if dist < 125 and e.cd <= 0:
			e.cd = stats.cooldown
			host._all("c_shot", [e.pos, player.pos, "arcane", 0.0])
			host._hurt_player(target, stats.dmg, e.id, "ranged")
	elif dist > stats.radius + 16:
		host._step(e, dir * speed * delta, stats)
	elif e.cd <= 0:
		e.phase = "windup"
		e.until = now + 800
