extends Node
## Хост: опыт и уровни, очки характеристик, ресурс класса (мана / ярость / энергия),
## умения классов по данным Rules.SKILLS (strike, bolt, multi, heal, buff, blink), усиления (баффы),
## расчёт удара по врагу с учётом характеристик и баффов, дальние атаки.

const Gifts := preload("res://scripts/gifts.gd")

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
		m *= maxf(0.0, 1.0 - 0.6 * float(p.get("gift_buff_power", {}).get("stoneskin", 1.0)))
	if has_buff(p, "barrier"):
		m *= maxf(0.0, 1.0 - 0.5 * float(p.get("gift_buff_power", {}).get("barrier", 1.0)))
	return maxf(m, Rules.MIN_DMG_TAKEN)                     # защита складывается, но не до бессмертия


# ---------- ресурс класса ----------

func init_res(p: Dictionary) -> void:
	p.res_max = Rules.res_max(p, host.gifts.factor(int(p.peer_id), "mana"))
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
		p.res_max = Rules.res_max(p, host.gifts.factor(pid, "mana"))
		add_res(p, 0.0)
		if Rules.res_kind(p) == "rage":
			var idle := now_ms() - maxi(int(p.get("hurt_at", 0)), int(p.get("atk_at", 0)))
			if idle > 5000:
				add_res(p, -RAGE_DECAY * delta)
		else:
			add_res(p, Rules.res_regen(p, host.gifts.factor(pid, "mana_regen")) * delta)
		if sync and [int(p.res), int(p.res_max)] != p.get("_res_sent", []):
			p._res_sent = [int(p.res), int(p.res_max)]
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
	var gifts = host.gifts
	var skill := bool(opts.get("skill", false))
	var ctx := {"eid": eid, "enemy": e, "skill": skill}
	var bonus := crit_bonus + float(gifts.mod(pid, "crit", ctx))
	if skill:
		bonus += float(gifts.mod(pid, "skill_crit", ctx))
	var crit := randf() < clampf(Rules.base_crit_chance(p) + bonus + float(p.get("gift_crit_chain", 0.0)), 0.0, Gifts.CAPS.crit)
	gifts.combat(pid, ctx)
	if Gifts.has_flag(p, "first_crit"):
		var hits: Dictionary = p.get_or_add("gift_first", {})
		crit = crit or not hits.has(eid)
		hits[eid] = true
	var cmult := 2.0 * float(gifts.factor(pid, "crit_dmg", ctx))
	if has_buff(p, "dirty_trick"):                   # подлый приём: гарантированный крит ×3
		crit = true
		cmult += float(p.get("gift_buff_power", {}).get("dirty_trick", 1.0))
		p.buffs.erase("dirty_trick")
	var gift_mult: float = gifts.attack_factor(pid, eid, skill, ctx)
	var dmg := Rules.base_damage(p) * mult * gift_mult * randf_range(0.85, 1.15) * (cmult if crit else 1.0)
	var sunder: Array = e.get("sunder", [0.0, 0])
	if now_ms() < int(sunder[1]):
		dmg *= 1.0 + float(sunder[0])
	if crit and Gifts.has_flag(p, "fate_blade"):
		p.gift_state.fate_blade = mini(2500, int(p.gift_state.get("fate_blade", 0)) + 1)
		host._send_self(pid)
	if Gifts.has_flag(p, "crit_chain"):
		p.gift_crit_chain = minf(Gifts.CAPS.crit, float(p.get("gift_crit_chain", 0.0)) + 0.10) if crit else 0.0
	if has_buff(p, "warcry"):
		dmg *= 1.0 + 0.4 * float(p.get("gift_buff_power", {}).get("warcry", 1.0))
	if int(p.get("riposte_until", 0)) > now_ms():          # ответный удар после парирования
		dmg *= float(p.get("gift_riposte", Rules.PARRY.riposte))
		p.erase("gift_riposte")
		p.riposte_until = 0
	if e.kind != "golem" and opts.has("execute") and float(e.hp) < float(e.max_hp) * float(opts.execute):
		dmg *= 2.0
	if e.kind != "golem" and Gifts.has_flag(p, "execute15") and gifts.ratio(e) < 0.15:
		dmg = maxf(dmg, e.hp)
	var d := maxi(1, int(dmg))
	var dealt := mini(int(e.hp), d)
	e.hp = maxi(0, int(e.hp) - d)
	host._all("c_enemy_hit", [eid, e.hp, d, crit])
	if opts.has("slow"):
		e.slow_until = now_ms() + int(float(opts.slow) * 1000.0 * (Gifts.BOSS_RULES.cc_mult if e.kind == "golem" else 1.0))
	var leech := clampf(float(opts.get("leech", 0.0)) + float(gifts.mod(pid, "lifesteal", ctx)), 0.0, Gifts.CAPS.lifesteal)
	_heal(pid, int(dealt * leech))
	ctx.damage = dealt
	ctx.raw_damage = d
	gifts.fire(pid, "hit", ctx)
	if e.hp <= 0 and host.enemies.has(eid):
		host._kill(eid, pid)
	gifts.after_attack(pid, eid, dealt, ctx)


## Бьёт всех врагов в круге. Возвращает, сколько задел.
func strike(pid: int, center: Vector2, radius: float, mult: float, crit_bonus: float, opts: Dictionary = {}) -> int:
	if opts.get("skill", false):
		radius *= host.gifts.factor(pid, "aoe")
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
func bolt(pid: int, dir: Vector2, reach: float, mult: float, aoe: float, crit_bonus: float, look: String, opts: Dictionary = {}) -> void:
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
	host._all("c_shot", [from, end, look, aoe * (host.gifts.factor(pid, "aoe") if opts.get("skill", false) else 1.0)])
	if best == -1:
		return
	if aoe > 0.0:
		strike(pid, host.enemies[best].pos, aoe, mult, crit_bonus, opts)
	else:
		hit_enemy(pid, best, mult, crit_bonus, opts)
		if Rules.res_kind(p) == "rage":
			add_res(p, RAGE_PER_HIT)


func _heal(pid: int, amount: int, from_skill: bool = false, caster: int = -1) -> void:
	var p: Dictionary = host.players[pid]
	if amount <= 0 or int(p.hp) <= 0 or (from_skill and Gifts.has_flag(p, "no_heal")):
		return
	amount = int(amount * host.gifts.factor(pid, "heal_taken"))
	var excess := maxi(0, int(p.hp) + amount - int(p.max_hp))
	if excess > 0 and Gifts.has_flag(p, "overheal_shield"):
		host.gifts.shield(pid, excess)
	var restored := mini(int(p.max_hp) - int(p.hp), amount)
	p.hp += restored
	if caster >= 0 and caster != pid and Gifts.has_flag(host.players[caster], "empath"):
		_heal(caster, int(restored * 0.30), from_skill)
	if host.gifts.ratio(p) >= 0.35:
		p.gift_low = false
	host._all("c_hp", [pid, p.hp, p.max_hp, 0])


func _allies_near(pos: Vector2, radius: float) -> Array:
	var out := []
	for pid in host.players:
		var o: Dictionary = host.players[pid]
		if int(o.hp) > 0 and o.pos.distance_to(pos) <= radius:
			out.append(pid)
	return out


# ---------- опыт и уровни ----------

func on_kill(killer: int, kind: String, pos: Vector2, ctx: Dictionary = {}) -> void:
	var xp: int = Rules.XP_FOR_KILL.get(kind, 5)
	for pid in host.players:
		var p: Dictionary = host.players[pid]
		if pid == killer or p.pos.distance_to(pos) <= Rules.SHARE_XP_RADIUS:
			give_xp(pid, xp, float(Rules.race_of(p).get("xp_mult", 1.0)), ctx)


func give_xp(pid: int, amount: int, race_mult: float = 1.0, ctx: Dictionary = {}) -> void:
	var p: Dictionary = host.players[pid]
	p.xp = int(p.xp) + int(amount * minf(1.0 + Gifts.CAPS.xp, race_mult * host.gifts.factor(pid, "xp", ctx)))
	var leveled := false
	while int(p.xp) >= Rules.xp_to_next(int(p.level)):
		p.xp = int(p.xp) - Rules.xp_to_next(int(p.level))
		p.level = int(p.level) + 1
		p.points = int(p.points) + Rules.POINTS_PER_LEVEL
		leveled = true
	if leveled:
		p.max_hp = Rules.max_hp(p, host.gifts.factor(pid, "hp"))
		if int(p.hp) > 0:
			p.hp = p.max_hp
		p.res_max = Rules.res_max(p, host.gifts.factor(pid, "mana"))
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
	p.max_hp = Rules.max_hp(p, host.gifts.factor(pid, "hp"))
	p.res_max = Rules.res_max(p, host.gifts.factor(pid, "mana"))
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
	var hp_cost := Rules.res_kind(p) == "mana" and Gifts.has_flag(p, "hp_cost")
	if hp_cost:
		if int(p.hp) <= cost:
			return
		p.hp -= cost
		host.gifts.health_events(pid, {})
		host._all("c_hp", [pid, p.hp, p.max_hp, 0])
	else:
		if float(p.get("res", 0.0)) < cost:
			return
		add_res(p, -cost)
	var cd := maxf(Gifts.CAPS.cd_mult_min, (1.0 + float(host.gifts.mod(pid, "cd"))) / (1.0 + Rules.stat(p, "spi") * 0.02))
	p.cds[id] = now_ms() + int(float(Rules.SKILLS[id].cd) * cd * 1000.0)
	perform(pid, id, dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT)


## Выполняет оплаченное умение или бесплатный повтор.
func perform(pid: int, id: String, dir: Vector2, repeat: bool = false) -> void:
	var p: Dictionary = host.players[pid]
	var sk: Dictionary = Rules.SKILLS[id]
	match str(sk.kind):
		"strike":
			var opts := {"skill": true}
			for k in ["slow", "execute", "leech"]:
				if sk.has(k):
					opts[k] = sk[k]
			strike(pid, p.pos + dir * float(sk.off), float(sk.r), float(sk.mult), float(sk.crit), opts)
		"bolt":
			bolt(pid, dir, float(sk.range), float(sk.mult), float(sk.aoe), float(sk.crit), str(sk.fx), {"skill": true})
		"multi":
			var n := int(sk.count)
			for i in n:
				var a := (i - (n - 1) / 2.0) * float(sk.spread)
				bolt(pid, dir.rotated(a), float(sk.range), float(sk.mult), 0.0, 0.0, str(sk.fx), {"skill": true})
		"heal":
			var amount := int((float(sk.base) + Rules.stat(p, "spi") * float(sk.spi)) * (1.0 + Rules.stat(p, "spi") * 0.04) * host.gifts.factor(pid, "heal"))
			var target := "allies" if Gifts.has_flag(p, "heal_splash") else str(sk.target)
			match target:
				"self":
					_heal(pid, amount, true, pid)
				"allies":
					for other in _allies_near(p.pos, float(sk.get("radius", 120.0)) * host.gifts.factor(pid, "aoe")):
						_heal(other, amount, true, pid)
				"lowest":
					var best := pid
					var worst := 2.0
					for other in _allies_near(p.pos, float(sk.get("radius", 120.0)) * host.gifts.factor(pid, "aoe")):
						var o: Dictionary = host.players[other]
						var ratio := float(o.hp) / maxf(1.0, float(o.max_hp))
						if ratio < worst:
							worst = ratio
							best = other
					_heal(best, amount, true, pid)
		"buff":
			var targets: Array = [pid] if float(sk.allies) <= 0.0 else _allies_near(p.pos, float(sk.allies))
			for other in targets:
				var powers: Dictionary = host.players[other].get_or_add("gift_buff_power", {})
				powers[sk.buff] = host.gifts.factor(pid, "buff_power")
				host.players[other].buffs[sk.buff] = now_ms() + int(float(sk.dur) * host.gifts.factor(pid, "buff_dur") * 1000.0)
				if other != pid:
					host._to(other, "c_announce", ["%s: %s!" % [p.name, sk.name], Color(1, 0.75, 0.4)])
					host._send_self(other)
		"blink":
			for i in 18:
				p.pos = World.move(p.pos, dir * 5.0)
			p.moved_at = now_ms()
			host._to(pid, "c_teleport", [p.pos, true])
	host._all("c_skill_fx", [pid, id, dir])
	if not repeat:
		host.gifts.fire(pid, "skill", {"id": id, "dir": dir})
	host._send_self(pid)


# ---------- базовая атака ----------

func basic_attack(pid: int, dir: Vector2) -> void:
	var p: Dictionary = host.players[pid]
	var style := Items.style_of(p.equip.get("weapon"))
	var st: Array = Rules.ATTACKS[style]          # перезарядка, урон, радиус, шанс крита, дальность
	var now := now_ms()
	var speed := Rules.attack_speed(p, host.gifts.mod(pid, "aspd") + host.gifts.buff_value(p, "aspd"))
	if now - int(p.get("atk_at", 0)) < int(float(st[0]) / speed):
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
