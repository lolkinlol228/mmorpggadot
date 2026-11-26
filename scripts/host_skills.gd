extends Node
## Хост: опыт и уровни, очки характеристик, умения (перезарядки, эффекты), усиления (баффы),
## расчёт удара по врагу с учётом характеристик, расы и баффов.

var host        # host_logic.gd


func now_ms() -> int:
	return Time.get_ticks_msec()


func has_buff(p: Dictionary, name: String) -> bool:
	return int(p.get("buffs", {}).get(name, 0)) > now_ms()


func cds_left(p: Dictionary) -> Dictionary:
	var out := {}
	for id in p.get("cds", {}):
		var left: float = (int(p.cds[id]) - now_ms()) / 1000.0
		if left > 0.0:
			out[id] = left
	return out


func buffs_left(p: Dictionary) -> Dictionary:
	var out := {}
	for id in p.get("buffs", {}):
		var left: float = (int(p.buffs[id]) - now_ms()) / 1000.0
		if left > 0.0:
			out[id] = left
	return out


# ---------- удар по врагу ----------

## Бьёт всех врагов в круге. mult — множитель урона умения/оружия, crit_bonus — добавка к шансу крита.
func strike(pid: int, center: Vector2, radius: float, mult: float, crit_bonus: float) -> void:
	var p: Dictionary = host.players[pid]
	for eid in host.enemies.keys():
		var e: Dictionary = host.enemies.get(eid, {})
		if e.is_empty() or e.pos.distance_to(center) > radius + Items.ENEMIES[e.kind].radius:
			continue
		var crit := randf() < Rules.crit_chance(p) + crit_bonus
		var cmult := 2.0
		if has_buff(p, "dirty_trick"):                   # подлый приём: гарантированный крит ×3
			crit = true
			cmult = 3.0
			p.buffs.erase("dirty_trick")
		var dmg := Rules.damage(p) * mult * randf_range(0.85, 1.15) * (cmult if crit else 1.0)
		if has_buff(p, "warcry"):
			dmg *= 1.4
		var d := int(dmg)
		e.hp -= d
		host._all("c_enemy_hit", [eid, e.hp, d, crit])
		if has_buff(p, "drain"):
			_heal(pid, int(d * 0.35))
		if e.hp <= 0:
			host._kill(eid, pid)


func _heal(pid: int, amount: int) -> void:
	var p: Dictionary = host.players[pid]
	if amount <= 0 or int(p.hp) <= 0:
		return
	p.hp = mini(int(p.max_hp), int(p.hp) + amount)
	host._all("c_hp", [pid, p.hp, p.max_hp, 0])


# ---------- опыт и уровни ----------

func on_kill(killer: int, kind: String, pos: Vector2) -> void:
	var xp: int = Rules.XP_FOR_KILL.get(kind, 5)
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		if pid == killer or p.pos.distance_to(pos) <= Rules.SHARE_XP_RADIUS:
			give_xp(pid, int(xp * float(Rules.race_of(p).get("xp_mult", 1.0))))


func give_xp(pid: int, amount: int) -> void:
	var p: Dictionary = host.players[pid]
	p.xp = int(p.xp) + amount
	var leveled := false
	while int(p.xp) >= Rules.xp_to_next(int(p.level)):
		p.xp = int(p.xp) - Rules.xp_to_next(int(p.level))
		p.level = int(p.level) + 1
		p.points = int(p.points) + Rules.POINTS_PER_LEVEL
		leveled = true
	if leveled:
		p.max_hp = Rules.max_hp(p)
		p.hp = p.max_hp
		host._all("c_levelup", [pid, int(p.level)])
		host._all("c_hp", [pid, p.hp, p.max_hp, 0])
	host._send_self(pid)


func add_stat(s: String) -> void:
	var pid: int = host._sender()
	var p = host.players.get(pid)
	if p == null or s not in Rules.STATS or int(p.points) <= 0:
		return
	p.points = int(p.points) - 1
	p.stats[s] = int(p.stats.get(s, 0)) + 1
	p.max_hp = Rules.max_hp(p)
	host._all("c_hp", [pid, p.hp, p.max_hp, 0])
	host._send_self(pid)


# ---------- умения ----------

func use(id: String, dir: Vector2) -> void:
	var pid: int = host._sender()
	var p = host.players.get(pid)
	if p == null or int(p.hp) <= 0 or not Rules.SKILLS.has(id) or not Rules.skill_unlocked(p, id):
		return
	if int(p.cds.get(id, 0)) > now_ms():
		return
	var sk: Dictionary = Rules.SKILLS[id]
	p.cds[id] = now_ms() + int(float(sk.cd) * Rules.cd_mult(p) * 1000.0)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	match id:
		"whirl":
			strike(pid, p.pos, 46.0, 1.2, 0.0)
		"smash":
			strike(pid, p.pos + dir * 28.0, 30.0, 2.5, 0.1)
		"mend":
			_heal(pid, int((30 + Rules.stat(p, "spi") * 3) * Rules.heal_power(p)))
		"second_wind":
			_heal(pid, int(30 * Rules.heal_power(p)))
		"warcry":                                        # союзникам рядом — тоже
			for other in host.players:
				var o: Dictionary = host.players[other]
				if o.pos.distance_to(p.pos) <= 120.0:
					o.buffs["warcry"] = now_ms() + int(sk.dur * 1000)
					if other != pid:
						host._to(other, "c_announce", ["%s: боевой клич! Урон +40%%" % p.name, Color(1, 0.5, 0.4)])
						host._send_self(other)
		"stoneskin", "drain", "pounce", "dirty_trick":
			p.buffs[id] = now_ms() + int(sk.dur * 1000)
	host._all("c_skill_fx", [pid, id, dir])
	host._send_self(pid)
