extends Node
## Хост: опыт и уровни, очки характеристик, ресурс класса (мана / ярость / энергия),
## умения классов по данным Rules.SKILLS (strike, bolt, multi, heal, buff, blink), усиления (баффы),
## расчёт удара по врагу с учётом характеристик и баффов, дальние атаки.

const RAGE_PER_HIT := 6.0
const RAGE_PER_HURT := 4.0
const RAGE_DECAY := 3.0          # в секунду, если 5 сек нет боя
const RES_SYNC := 0.25           # как часто слать ресурс владельцу

var host        # host_logic.gd
var _res_acc := 0.0


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


## Множитель получаемого урона от баффов (каменная кожа, щит веры, божественный щит).
func damage_taken_mult(p: Dictionary) -> float:
	if has_buff(p, "divine"):
		return 0.0
	var m := 1.0
	if has_buff(p, "stoneskin"):
		m *= 0.4
	if has_buff(p, "barrier"):
		m *= 0.5
	return maxf(m, Rules.MIN_DMG_TAKEN)                     # защита складывается, но не до бессмертия


# ---------- ресурс класса ----------

func init_res(p: Dictionary) -> void:
	p.res_max = Rules.res_max(p)
	p.res = 0.0 if Rules.res_kind(p) == "rage" else float(p.res_max)


func add_res(p: Dictionary, amount: float) -> void:
	p.res = clampf(float(p.get("res", 0.0)) + amount, 0.0, float(p.get("res_max", 100)))


func res_tick(delta: float) -> void:
	_res_acc += delta
	var sync := _res_acc >= RES_SYNC
	if sync:
		_res_acc = 0.0
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		if int(p.hp) <= 0:
			continue
		p.res_max = Rules.res_max(p)
		if Rules.res_kind(p) == "rage":
			var idle := now_ms() - maxi(int(p.get("hurt_at", 0)), int(p.get("atk_at", 0)))
			if idle > 5000:
				add_res(p, -RAGE_DECAY * delta)
		else:
			add_res(p, Rules.res_regen(p) * delta)
		if sync and int(p.res) != int(p.get("_res_sent", -1)):
			p._res_sent = int(p.res)
			host._to(pid, "c_res", [int(p.res), int(p.res_max)])


func on_hurt(pid: int) -> void:
	var p: Dictionary = host.players[pid]
	if Rules.res_kind(p) == "rage":
		add_res(p, RAGE_PER_HURT)


# ---------- удар по врагу ----------

## Один удар по одному врагу. opts: slow (сек), execute (порог здоровья для ×2), leech (доля урона в лечение).
func hit_enemy(pid: int, eid: int, mult: float, crit_bonus: float, opts: Dictionary = {}) -> void:
	var p: Dictionary = host.players[pid]
	var e: Dictionary = host.enemies.get(eid, {})
	if e.is_empty():
		return
	var crit := randf() < Rules.crit_chance(p) + crit_bonus
	var cmult := 2.0
	if has_buff(p, "dirty_trick"):                   # подлый приём: гарантированный крит ×3
		crit = true
		cmult = 3.0
		p.buffs.erase("dirty_trick")
	var dmg := Rules.damage(p) * mult * randf_range(0.85, 1.15) * (cmult if crit else 1.0)
	if has_buff(p, "warcry"):
		dmg *= 1.4
	if int(p.get("riposte_until", 0)) > now_ms():          # ответный удар после парирования
		dmg *= Rules.PARRY.riposte
		p.riposte_until = 0
	if opts.has("execute") and float(e.hp) < float(e.max_hp) * float(opts.execute):
		dmg *= 2.0
	var d := int(dmg)
	e.hp -= d
	host._all("c_enemy_hit", [eid, e.hp, d, crit])
	if opts.has("slow"):
		e.slow_until = now_ms() + int(float(opts.slow) * 1000.0)
	if opts.has("leech"):
		_heal(pid, int(d * float(opts.leech)))
	if e.hp <= 0:
		host._kill(eid, pid)


## Бьёт всех врагов в круге. Возвращает, сколько задел.
func strike(pid: int, center: Vector2, radius: float, mult: float, crit_bonus: float, opts: Dictionary = {}) -> int:
	var n := 0
	for eid in host.enemies.keys():
		var e: Dictionary = host.enemies.get(eid, {})
		if e.is_empty() or e.pos.distance_to(center) > radius + Items.ENEMIES[e.kind].radius:
			continue
		hit_enemy(pid, eid, mult, crit_bonus, opts)
		n += 1
	if n > 0 and Rules.res_kind(host.players[pid]) == "rage":
		add_res(host.players[pid], RAGE_PER_HIT)
	return n


## Снаряд по прямой: попадает в первого врага на пути. aoe > 0 — взрыв вокруг точки попадания.
func bolt(pid: int, dir: Vector2, reach: float, mult: float, aoe: float, crit_bonus: float, look: String) -> void:
	var p: Dictionary = host.players[pid]
	var from: Vector2 = p.pos
	var best_t := reach
	var best := -1
	for eid in host.enemies:
		var e: Dictionary = host.enemies[eid]
		var rel: Vector2 = e.pos - from
		var t := rel.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		if absf(rel.cross(dir)) <= float(Items.ENEMIES[e.kind].radius) + 6.0:
			best_t = t
			best = eid
	var end := from + dir * best_t
	host._all("c_shot", [from, end, look, aoe])
	if best == -1:
		return
	if aoe > 0.0:
		strike(pid, host.enemies[best].pos, aoe, mult, crit_bonus)
	else:
		hit_enemy(pid, best, mult, crit_bonus)
		if Rules.res_kind(p) == "rage":
			add_res(p, RAGE_PER_HIT)


func _heal(pid: int, amount: int) -> void:
	var p: Dictionary = host.players[pid]
	if amount <= 0 or int(p.hp) <= 0:
		return
	p.hp = mini(int(p.max_hp), int(p.hp) + amount)
	host._all("c_hp", [pid, p.hp, p.max_hp, 0])


func _allies_near(pos: Vector2, radius: float) -> Array:
	var out := []
	for pid in host.players:
		var o: Dictionary = host.players[pid]
		if int(o.hp) > 0 and o.pos.distance_to(pos) <= radius:
			out.append(pid)
	return out


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
		p.res_max = Rules.res_max(p)
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
	p.res_max = Rules.res_max(p)
	host._all("c_hp", [pid, p.hp, p.max_hp, 0])
	host._send_self(pid)


# ---------- умения ----------

func use(id: String, dir: Vector2) -> void:
	var pid: int = host._sender()
	var p = host.players.get(pid)
	if p == null or int(p.hp) <= 0 or not Rules.SKILLS.has(id) or id not in Rules.class_skills(p):
		return
	if not Rules.skill_unlocked(p, id) or not Rules.has_class_weapon(p) or int(p.cds.get(id, 0)) > now_ms():
		return
	var cost := Rules.skill_cost(p, id)
	if float(p.get("res", 0.0)) < cost:
		return
	var sk: Dictionary = Rules.SKILLS[id]
	add_res(p, -cost)
	p.cds[id] = now_ms() + int(float(sk.cd) * Rules.cd_mult(p) * 1000.0)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	match str(sk.kind):
		"strike":
			var opts := {}
			for k in ["slow", "execute", "leech"]:
				if sk.has(k):
					opts[k] = sk[k]
			strike(pid, p.pos + dir * float(sk.off), float(sk.r), float(sk.mult), float(sk.crit), opts)
		"bolt":
			bolt(pid, dir, float(sk.range), float(sk.mult), float(sk.aoe), float(sk.crit), str(sk.fx))
		"multi":
			var n := int(sk.count)
			for i in n:
				var a := (i - (n - 1) / 2.0) * float(sk.spread)
				bolt(pid, dir.rotated(a), float(sk.range), float(sk.mult), 0.0, 0.0, str(sk.fx))
		"heal":
			var amount := int((float(sk.base) + Rules.stat(p, "spi") * float(sk.spi)) * Rules.heal_power(p))
			match str(sk.target):
				"self":
					_heal(pid, amount)
				"allies":
					for other in _allies_near(p.pos, float(sk.radius)):
						_heal(other, amount)
				"lowest":
					var best := pid
					var worst := 2.0
					for other in _allies_near(p.pos, float(sk.radius)):
						var o: Dictionary = host.players[other]
						var ratio := float(o.hp) / maxf(1.0, float(o.max_hp))
						if ratio < worst:
							worst = ratio
							best = other
					_heal(best, amount)
		"buff":
			var targets: Array = [pid] if float(sk.allies) <= 0.0 else _allies_near(p.pos, float(sk.allies))
			for other in targets:
				host.players[other].buffs[sk.buff] = now_ms() + int(float(sk.dur) * 1000.0)
				if other != pid:
					host._to(other, "c_announce", ["%s: %s!" % [p.name, sk.name], Color(1, 0.75, 0.4)])
					host._send_self(other)
	host._all("c_skill_fx", [pid, id, dir])
	host._send_self(pid)


# ---------- базовая атака ----------

func basic_attack(pid: int, dir: Vector2) -> void:
	var p: Dictionary = host.players[pid]
	var style := Items.style_of(p.equip.get("weapon"))
	var st: Array = Rules.ATTACKS[style]          # перезарядка, урон, радиус, шанс крита, дальность
	var now := now_ms()
	if now - int(p.get("atk_at", 0)) < int(float(st[0]) / Rules.attack_speed(p)):
		return
	p.atk_at = now
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	host._all("c_swing", [pid, dir])
	if style in ["bolt", "shot"]:
		var w: Dictionary = p.equip.get("weapon", {})
		var look := "arrow" if style == "shot" else ("holy" if w.get("base", "") == "wand" else "arcane")
		bolt(pid, dir, float(st[4]), float(st[1]), 0.0, float(st[3]), look)
	else:
		strike(pid, p.pos + dir * float(st[4]), float(st[2]), float(st[1]), float(st[3]))
