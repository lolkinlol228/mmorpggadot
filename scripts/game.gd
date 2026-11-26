extends Node2D
## Мир игры. Хост (peer 1) — единственный, кто решает: бой, лут, инвентари, обмены.
## Клиенты шлют хосту намерения (h_*), хост рассылает результаты (c_*).
## Поэтому этот же код потом можно запустить как выделенный сервер.

const PlayerView := preload("res://scripts/player_view.gd")
const EnemyView := preload("res://scripts/enemy_view.gd")
const LootView := preload("res://scripts/loot_view.gd")
const Ground := preload("res://scripts/ground.gd")
const Fx := preload("res://scripts/fx.gd")
const GameUI := preload("res://scripts/ui.gd")
const HostLogic := preload("res://scripts/host_logic.gd")
const PropsLayer := preload("res://scripts/props_layer.gd")
const Ambience := preload("res://scripts/ambience.gd")
const Interact := preload("res://scripts/interact.gd")
var interact
var open_spot := -1

var WORLD_SIZE := Vector2(2400, 1600)   # берутся из карты (World) в _ready
var SPAWN := Vector2(1020, 1005)
const SPEED := 120.0
const NET_TICK := 0.05
const PICKUP_RADIUS := 26.0
const TRADE_RANGE := 160.0
const GREY := Color(0.65, 0.65, 0.72)

var is_host := false
var my_id := 1
var me := {}                 # своё полное состояние: inv, equip, gold, hp
var my_pos := SPAWN
var my_facing := Vector2.RIGHT
var camera: Camera2D
var ui
var fx
var host                     # HostLogic, есть только у хоста
var entities: Node2D          # всё, что стоит на земле, с сортировкой по Y

var player_views := {}
var enemy_views := {}
var loot_views := {}
var pending_pickup := {}
var send_acc := 0.0
var last_attack := 0
var full_hint_at := 0
var step_acc := 0.0
var stamina := 100.0
var stamina_idle := 0.0
var dash_left := 0.0
var dash_dir := Vector2.ZERO
var dust_acc := 0.0
const SPRINT := 1.55
const DASH_SPEED := 3.3
const DASH_COST := 30.0
const ATTACK_CD := {"slash": 340, "chop": 520, "stab": 220, "bolt": 560, "shot": 500}


func _ready() -> void:
	randomize()
	is_host = multiplayer.is_server()
	my_id = multiplayer.get_unique_id()
	WORLD_SIZE = World.size
	SPAWN = World.spawn
	my_pos = SPAWN
	add_child(Ground.new())
	var shadows := Node2D.new()      # тени объектов — под всеми, кто стоит на земле
	add_child(shadows)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	var pl := PropsLayer.new()
	add_child(pl)
	pl.populate(entities, shadows)
	var amb := Ambience.new()
	amb.game = self
	add_child(amb)
	amb.build(entities)
	interact = Interact.new()
	interact.game = self
	add_child(interact)
	camera = Camera2D.new()
	camera.limit_right = int(WORLD_SIZE.x)
	camera.limit_bottom = int(WORLD_SIZE.y)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.position = SPAWN
	add_child(camera)
	fx = Fx.new()
	fx.game = self
	add_child(fx)
	ui = GameUI.new()
	ui.game = self
	add_child(ui)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var char_data := Save.load_char(Net.player_name, Net.player_class, Net.player_gifts)
	if not Net.player_look.is_empty():
		char_data.look = Net.player_look
	if is_host:
		host = HostLogic.new()
		host.game = self
		add_child(host)
		multiplayer.peer_disconnected.connect(host.on_peer_disconnected)
		h_register(char_data)
		host.start_world()
		ui.add_feed("Мир создан на порту %d. Друзья подключаются по твоему IP." % Net.port, Color(0.7, 0.9, 1.0))
	else:
		rpc_id(1, "h_register", char_data)
	ui.add_feed("WASD — ходьба · Shift — бег · Пробел — рывок · ЛКМ — удар · ПКМ/F — парирование · E — взаимодействие · I — сумка", GREY)
	ui.add_feed("1 2 3 4 — умения класса (открываются с уровнем) · C — герой, класс и дары", GREY)
	_maybe_autotest()


func _maybe_autotest() -> void:
	if not OS.is_debug_build():
		return
	var args := OS.get_cmdline_user_args()
	if not args.has("--autotest"):
		return
	var tester = load("res://scripts/debug_autotest.gd").new()
	tester.game = self
	for a in args:
		if a.begins_with("--shots="):
			tester.shots_dir = a.trim_prefix("--shots=")
	add_child(tester)


func _process(delta: float) -> void:
	_move_local(delta)
	if open_spot >= 0 and ui.shop.mode != "":           # отошёл — окно закрывается
		var sp: Dictionary = interact.spot(open_spot)
		if Vector2(sp.x, sp.y).distance_to(my_pos) > 90.0:
			ui.shop.close_all()
			open_spot = -1
	camera.position = my_pos
	_auto_pickup()


func _move_local(delta: float) -> void:
	if me.is_empty() or int(me.hp) <= 0 or ui.is_typing():
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	var sprint: bool = Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector2.ZERO and stamina > 1.0
	if dash_left > 0.0:                                  # рывок: летим по направлению, ввод игнорируется
		dash_left -= delta
		my_pos = World.move(my_pos, dash_dir * SPEED * DASH_SPEED * delta)
	elif dir != Vector2.ZERO:
		my_pos = World.move(my_pos, dir.normalized() * SPEED * move_mult() * (SPRINT if sprint else 1.0) * delta)
		step_acc += delta * (1.5 if sprint else 1.0)
		if step_acc > 0.3:
			step_acc = 0.0
			Sfx.play("step")
	if sprint and dash_left <= 0.0:
		stamina = maxf(0.0, stamina - 26.0 * delta)
		stamina_idle = 0.0
		dust_acc += delta
		if dust_acc > 0.12:
			dust_acc = 0.0
			fx.dust(my_pos)
	else:
		stamina_idle += delta
		if stamina_idle > 0.6:
			stamina = minf(100.0, stamina + 24.0 * Rules.stamina_regen(me) * delta)
	ui.hud.set_stamina(stamina / 100.0)
	var aim := get_global_mouse_position() - my_pos
	if aim.length() > 6.0:
		my_facing = aim.normalized()
	var view = player_views.get(my_id)
	if view:
		view.position = my_pos
		view.target = my_pos
		view.facing = my_facing
	send_acc += delta
	if send_acc >= NET_TICK and not is_host:
		send_acc = 0.0
		rpc_id(1, "h_pos", my_pos, my_facing)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sp: Dictionary = interact.spot(interact.focused) if interact.focused >= 0 else {}
		var aim := get_global_mouse_position()
		if not sp.is_empty() and aim.distance_to(Vector2(sp.x, sp.y) - Vector2(0, float(sp.h) * 0.5)) < 14.0:
			use_spot()
		else:
			attack()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		parry()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				dash()
			KEY_F:
				parry()
			KEY_I, KEY_TAB:
				ui.toggle_inventory()
			KEY_T:
				request_trade_nearest()
			KEY_E:
				use_spot()
			KEY_C:
				ui.charwin.toggle()
			KEY_1, KEY_2, KEY_3, KEY_4:
				var ids: Array = ui.hud.skills.ids
				var i: int = {KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3}[event.physical_keycode]
				if i < ids.size():
					use_skill(ids[i])
			KEY_ENTER, KEY_KP_ENTER:
				ui.open_chat()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				ui.close_panels()
			KEY_F9:
				if is_host and OS.is_debug_build():
					host.debug_jackpot()


# ---------- действия игрока (уходят хосту) ----------

func _to_host(method: StringName, args: Array = []) -> void:
	if is_host:
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


func dash() -> void:
	var free: bool = not me.is_empty() and ui.hud.skills.has_buff("pounce")     # кошачья прыть: рывки бесплатно
	if me.is_empty() or int(me.hp) <= 0 or dash_left > 0.0 or (stamina < DASH_COST and not free):
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1
	dash_dir = dir.normalized() if dir != Vector2.ZERO else my_facing
	dash_left = 0.2
	if not free:
		stamina -= DASH_COST
	stamina_idle = 0.0
	fx.dust(my_pos, 10)
	Sfx.play("swing", -2.0, 0.7)
	_to_host("h_dash")


func attack() -> void:
	if me.is_empty() or int(me.hp) <= 0:
		return
	var now := Time.get_ticks_msec()
	var style: String = Items.style_of(me.equip.get("weapon"))
	if now - last_attack < int(float(ATTACK_CD[style]) / Rules.attack_speed(me)):
		return
	last_attack = now
	_to_host("h_attack", [my_facing])


var parry_ready_at := 0

## Парирование (ПКМ / F): тратит выносливость, само окно и исход решает хост.
func parry() -> void:
	if me.is_empty() or int(me.hp) <= 0:
		return
	if not Rules.can_parry(me):
		ui.add_feed("Парировать можно только оружием ближнего боя.", GREY)
		return
	var now := Time.get_ticks_msec()
	if now < parry_ready_at or stamina < Rules.PARRY.cost:
		return
	parry_ready_at = now + int(Rules.PARRY.cd * 1000.0)
	stamina -= Rules.PARRY.cost
	stamina_idle = 0.0
	_to_host("h_parry")


@rpc("any_peer", "call_remote", "reliable")
func h_parry() -> void:
	if host: host.parry()

@rpc("authority", "call_remote", "reliable")
func c_parry(pid: int) -> void:
	var v = player_views.get(pid)
	if v:
		v.parry()

## Удачное парирование: искры, звон, надпись. Себе — сразу снова готово.
@rpc("authority", "call_remote", "reliable")
func c_parried(pid: int, enemy_pos: Vector2) -> void:
	var v = player_views.get(pid)
	if v == null:
		return
	var mid: Vector2 = v.position.lerp(enemy_pos, 0.45) + Vector2(0, -14)
	fx.burst(mid, Color(1.0, 0.9, 0.55), 18, false)
	float_text(v.position + Vector2(0, -46), "Парировано!", Color(1.0, 0.9, 0.55))
	Sfx.play_at("bell", v.position, my_pos)
	if pid == my_id:
		parry_ready_at = Time.get_ticks_msec() + 600
		fx.shake = 0.12


func move_mult() -> float:
	if me.is_empty():
		return 1.0
	return Rules.speed_mult(me) * (1.4 if ui.hud.skills.has_buff("pounce") else 1.0)


## Умение с панели. Лунный шаг двигает самого игрока (позицию ведёт клиент), остальное решает хост.
func use_skill(id: String) -> void:
	if me.is_empty() or int(me.hp) <= 0:
		return
	var bar = ui.hud.skills
	if not Rules.skill_unlocked(me, id):
		ui.add_feed("%s откроется на %d уровне." % [Rules.SKILLS[id].name, Rules.skill_level(me, id)], GREY)
		return
	if not Rules.has_class_weapon(me):
		var names := PackedStringArray()
		for b in Rules.class_of(me).weapons:
			names.append(Items.BASES[b].name.to_lower())
		ui.add_feed("Умения класса работают только со своим оружием: %s." % ", ".join(names), GREY)
		return
	if bar.cd_left(id) > 0.0:
		return
	if float(me.get("res", 0)) < Rules.skill_cost(me, id):
		ui.add_feed("Не хватает: %s." % Rules.RES_NAMES[Rules.res_kind(me)].to_lower(), GREY)
		return
	bar.start_cd(id)
	if id == "blink":
		fx.burst(my_pos + Vector2(0, -12), Color(0.6, 0.75, 1.0), 14, false)
		for i in 18:
			my_pos = World.move(my_pos, my_facing * 5.0)
		fx.burst(my_pos + Vector2(0, -12), Color(0.8, 0.9, 1.0), 14, false)
		if not is_host:
			rpc_id(1, "h_pos", my_pos, my_facing)
	_to_host("h_skill", [id, my_facing])


func add_stat(s: String) -> void:
	_to_host("h_stat", [s])


func request_equip(uid: String) -> void:
	_to_host("h_equip", [uid])


func request_unequip(slot: String) -> void:
	_to_host("h_unequip", [slot])


func request_trade_nearest() -> void:
	var best := -1
	var best_d := TRADE_RANGE
	for pid in player_views:
		if pid == my_id:
			continue
		var d: float = player_views[pid].position.distance_to(my_pos)
		if d < best_d:
			best_d = d
			best = pid
	if best == -1:
		ui.add_feed("Подойди вплотную к другому игроку и нажми T, чтобы предложить обмен.", GREY)
		return
	_to_host("h_trade_req", [best])


func answer_trade(from: int, accept: bool) -> void:
	_to_host("h_trade_answer", [from, accept])


func send_trade_offer(uids: Array) -> void:
	_to_host("h_trade_offer", [uids])


func confirm_trade() -> void:
	_to_host("h_trade_confirm")


func cancel_trade() -> void:
	_to_host("h_trade_cancel")


## Взаимодействие с отмеченным объектом (хранилище, лавка, доска, житель).
func use_spot() -> void:
	if interact.focused < 0 or me.is_empty() or int(me.hp) <= 0:
		return
	var sp: Dictionary = interact.spot(interact.focused)
	if Vector2(sp.x, sp.y).distance_to(my_pos) > 70.0:
		ui.add_feed("Подойди ближе.", GREY)
		return
	open_spot = interact.focused
	if player_views.has(my_id):
		player_views[my_id].use()
	ui.shop.open(sp.kind, sp)


func eco(op: String, arg := "") -> void:
	_to_host("h_eco", [op, arg])


func send_chat(text: String) -> void:
	_to_host("h_chat", [text])


func leave_game() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _auto_pickup() -> void:
	if me.is_empty() or int(me.hp) <= 0:
		return
	var now := Time.get_ticks_msec()
	for lid in loot_views:
		if loot_views[lid].position.distance_to(my_pos) > PICKUP_RADIUS:
			continue
		if me.inv.size() >= Items.MAX_INV and loot_views[lid].item.base != "coins":
			if now - full_hint_at > 4000:
				full_hint_at = now
				ui.add_feed("Сумка полна! Выкинуть пока нельзя — надень лучшее или обменяй.", GREY)
			return
		if now - int(pending_pickup.get(lid, -100000)) > 1500:
			pending_pickup[lid] = now
			_to_host("h_pickup", [lid])


func _on_server_disconnected() -> void:
	Net.last_error = "Хост закрыл мир или связь потеряна."
	leave_game()


# ---------- входящие запросы к хосту (вся логика в host_logic.gd) ----------

@rpc("any_peer", "call_remote", "reliable")
func h_register(data: Dictionary) -> void:
	if host: host.register(data)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func h_pos(pos: Vector2, facing: Vector2) -> void:
	if host: host.update_pos(pos, facing)

@rpc("any_peer", "call_remote", "reliable")
func h_attack(dir: Vector2) -> void:
	if host: host.attack(dir)

@rpc("any_peer", "call_remote", "reliable")
func h_pickup(lid: int) -> void:
	if host: host.pickup(lid)

@rpc("any_peer", "call_remote", "reliable")
func h_equip(uid: String) -> void:
	if host: host.equip(uid)

@rpc("any_peer", "call_remote", "reliable")
func h_unequip(slot: String) -> void:
	if host: host.unequip(slot)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_req(target: int) -> void:
	if host: host.trade_request(target)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_answer(from: int, accept: bool) -> void:
	if host: host.trade_answer(from, accept)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_offer(uids: Array) -> void:
	if host: host.trade_offer(uids)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_confirm() -> void:
	if host: host.trade_confirm()

@rpc("any_peer", "call_remote", "reliable")
func h_trade_cancel() -> void:
	if host: host.trade_cancel()

@rpc("any_peer", "call_remote", "reliable")
func h_dash() -> void:
	if host: host.dash()

@rpc("authority", "call_remote", "reliable")
func c_dash(pid: int) -> void:
	var v = player_views.get(pid)
	if v:
		v.dash()

@rpc("any_peer", "call_remote", "reliable")
func h_chat(text: String) -> void:
	if host: host.chat(text)

@rpc("any_peer", "call_remote", "reliable")
func h_skill(id: String, dir: Vector2) -> void:
	if host: host.skills.use(id, dir)

@rpc("any_peer", "call_remote", "reliable")
func h_stat(s: String) -> void:
	if host: host.skills.add_stat(s)

@rpc("authority", "call_remote", "reliable")
func c_skill_fx(pid: int, id: String, dir: Vector2) -> void:
	var v = player_views.get(pid)
	if v:
		v.skill(id, dir)
		Sfx.play_at({"heal": "shimmer", "buff": "bell", "blink": "swing", "bolt": "swing", "multi": "swing"}.get(str(Rules.SKILLS[id].kind), "swing"), v.position, my_pos)
		var sk: Dictionary = Rules.SKILLS[id]
		if sk.kind == "strike" and float(sk.mult) >= 2.0:     # тяжёлые удары поднимают пыль и трясут камеру
			fx.dust(v.position + dir * float(sk.off), 12)
			if pid == my_id:
				fx.shake = 0.25

## Ресурс класса (мана / ярость / энергия) — шлётся чаще, чем всё остальное о себе.
@rpc("authority", "call_remote", "unreliable_ordered")
func c_res(value: int, max_value: int) -> void:
	if me.is_empty():
		return
	me.res = value
	me.res_max = max_value
	ui.hud.set_res(me)


## Видимый снаряд (стрела, шар, луч). Попадание уже посчитано хостом.
@rpc("authority", "call_remote", "reliable")
func c_shot(from: Vector2, to: Vector2, kind: String, boom: float) -> void:
	var pr = preload("res://scripts/projectile.gd").new()
	pr.from = from
	pr.to = to
	pr.kind = kind
	pr.boom = boom
	pr.game = self
	add_child(pr)

@rpc("authority", "call_remote", "reliable")
func c_levelup(pid: int, level: int) -> void:
	var v = player_views.get(pid)
	if v:
		fx.burst(v.position + Vector2(0, -14), Color(1, 0.85, 0.4), 40, true)
		float_text(v.position + Vector2(0, -52), "УРОВЕНЬ %d!" % level, Color(1, 0.85, 0.4))
		ui.add_feed("%s достиг %d уровня!" % [v.pname, level], Color(1, 0.85, 0.4))
	if pid == my_id:
		Sfx.fanfare(2)

@rpc("any_peer", "call_remote", "reliable")
func h_eco(op: String, arg: String) -> void:
	if host: host.eco.handle(op, arg)


# ---------- сообщения от хоста (картинка и интерфейс) ----------

@rpc("authority", "call_remote", "reliable")
func c_init(ps: Array, es: Array, ls: Array, priv: Dictionary) -> void:
	for p in ps:
		c_player_joined(p)
	for e in es:
		c_enemy_spawn(e)
	for l in ls:
		_add_loot(l[0], l[1], l[2], false)
	my_pos = priv.pos
	c_self(priv)
	print("[client] в мире: игроков %d, врагов %d" % [player_views.size(), enemy_views.size()])


@rpc("authority", "call_remote", "reliable")
func c_self(priv: Dictionary) -> void:
	if not me.is_empty() and int(priv.coins) > int(me.coins):
		Sfx.play("coins")
	var old_level := int(me.get("level", 0))
	me = priv
	me["_recv"] = Time.get_ticks_msec()
	ui.refresh()
	if old_level > 0 and int(me.level) > old_level and int(me.points) > 0:
		ui.add_feed("Новые очки характеристик! Открой окно героя: C", Color(1, 0.85, 0.4))
	Save.store_char({"name": Net.player_name, "coins": me.coins, "inv": me.inv, "equip": me.equip,
		"look": me.get("look", {}), "bank": me.get("bank", []), "bounties": me.get("bounties", {}),
		"level": me.get("level", 1), "xp": me.get("xp", 0), "points": me.get("points", 0), "stats": me.get("stats", {}),
		"cls": me.get("cls", "warrior"), "gifts": me.get("gifts", [])})


@rpc("authority", "call_remote", "reliable")
func c_player_joined(pub: Dictionary) -> void:
	var pid := int(pub.id)
	if player_views.has(pid):
		return
	var v := PlayerView.new()
	v.pid = pid
	v.pname = pub.name
	v.equip = pub.equip
	v.look = pub.get("look", {})
	v.hp = pub.hp
	v.max_hp = pub.max_hp
	v.is_me = pid == my_id
	v.position = pub.pos
	v.target = pub.pos
	entities.add_child(v)
	player_views[pid] = v


@rpc("authority", "call_remote", "reliable")
func c_player_left(pid: int) -> void:
	if player_views.has(pid):
		player_views[pid].queue_free()
		player_views.erase(pid)


@rpc("authority", "call_remote", "unreliable_ordered")
func c_state(ps: Array, es: Array) -> void:
	for p in ps:
		var v = player_views.get(p[0])
		if v and p[0] != my_id:
			v.target = p[1]
			v.facing = p[2]
	for e in es:
		var ev = enemy_views.get(e[0])
		if ev:
			ev.target = e[1]


@rpc("authority", "call_remote", "reliable")
func c_enemy_spawn(d: Array) -> void:
	var v := EnemyView.new()
	v.setup(d[1], d[2], d[3], d[4])
	entities.add_child(v)
	enemy_views[d[0]] = v


@rpc("authority", "call_remote", "reliable")
func c_enemy_hit(eid: int, hp: int, dmg: int, crit: bool) -> void:
	var v = enemy_views.get(eid)
	if v:
		v.hp = hp
		v.flash()
		Sfx.play_at("hit_stone" if v.kind == "golem" else ("crit" if crit else "hit"), v.position, my_pos)
		float_text(v.position + Vector2(0, -30), ("%d!" % dmg) if crit else str(dmg),
			Color(1, 0.85, 0.2) if crit else Color.WHITE)


@rpc("authority", "call_remote", "reliable")
func c_enemy_died(eid: int) -> void:
	var v = enemy_views.get(eid)
	if v:
		fx.burst(v.position, v.data.color, 24, false)
		Sfx.play_at("enemy_die", v.position, my_pos)
		v.queue_free()
		enemy_views.erase(eid)


@rpc("authority", "call_remote", "reliable")
func c_swing(pid: int, dir: Vector2) -> void:
	var v = player_views.get(pid)
	if v:
		v.swing(dir)
		Sfx.play_at("swing", v.position, my_pos)


@rpc("authority", "call_remote", "reliable")
func c_hp(pid: int, hp: int, max_hp: int, dealt: int) -> void:
	var v = player_views.get(pid)
	if v:
		v.hp = hp
		v.max_hp = max_hp
		if dealt > 0:
			v.hurt()
			float_text(v.position + Vector2(0, -44), "-%d" % dealt, Color(1, 0.35, 0.3))
	if pid == my_id and not me.is_empty():
		me.hp = hp
		me.max_hp = max_hp
		ui.refresh_hp()
		if dealt > 0:
			fx.hurt()
			Sfx.play("hurt")


@rpc("authority", "call_remote", "reliable")
func c_teleport(pos: Vector2) -> void:
	my_pos = pos


@rpc("authority", "call_remote", "reliable")
func c_equip(pid: int, equip: Dictionary) -> void:
	var v = player_views.get(pid)
	if v:
		v.set_equip(equip)
	if pid == my_id:
		Sfx.play("equip_metal" if equip.has("weapon") and randf() < 0.5 else "equip_cloth")


@rpc("authority", "call_remote", "reliable")
func c_loot(lid: int, item: Dictionary, pos: Vector2) -> void:
	_add_loot(lid, item, pos, true)


func _add_loot(lid: int, item: Dictionary, pos: Vector2, fresh: bool) -> void:
	var v := LootView.new()
	v.item = item
	v.position = pos
	entities.add_child(v)
	loot_views[lid] = v
	if fresh and Items.is_jackpot(item):
		fx.drop_appeared(pos, item)
		ui.add_feed("Что-то ослепительно сверкнуло на земле!", Items.color(item))
	elif fresh and int(item.rarity) >= 2:
		fx.burst(pos, Items.color(item), 16, false)
		Sfx.play_at("shimmer", pos, my_pos)


@rpc("authority", "call_remote", "reliable")
func c_loot_gone(lid: int) -> void:
	if loot_views.has(lid):
		if pending_pickup.has(lid):
			Sfx.play("pickup")
		loot_views[lid].queue_free()
		loot_views.erase(lid)
	pending_pickup.erase(lid)


@rpc("authority", "call_remote", "reliable")
func c_jackpot(finder: String, item: Dictionary) -> void:
	fx.jackpot(finder, item)
	Sfx.fanfare(int(item.rarity) + 1)
	ui.add_feed("⚡ %s нашёл %s [%s]" % [finder, Items.display_name(item),
		Items.RARITY_NAMES[int(item.rarity)]], Items.color(item))


@rpc("authority", "call_remote", "reliable")
func c_chat(from: String, text: String) -> void:
	ui.hud.add_chat(from, text)
	Sfx.play("hover")


@rpc("authority", "call_remote", "reliable")
func c_announce(text: String, color: Color) -> void:
	ui.add_feed(text, color)


@rpc("authority", "call_remote", "reliable")
func c_trade_invite(from: int, from_name: String) -> void:
	ui.show_invite(from, from_name)


@rpc("authority", "call_remote", "reliable")
func c_trade_open(other_name: String) -> void:
	ui.open_trade(other_name)


@rpc("authority", "call_remote", "reliable")
func c_trade_state(mine: Array, theirs: Array, my_ok: bool, their_ok: bool) -> void:
	ui.set_trade_state(mine, theirs, my_ok, their_ok)


@rpc("authority", "call_remote", "reliable")
func c_trade_closed(msg: String) -> void:
	ui.close_trade(msg)


func float_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.z_index = 20
	l.position = pos + Vector2(-30, 0)
	l.size = Vector2(60, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", pos.y - 20, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_callback(l.queue_free)
