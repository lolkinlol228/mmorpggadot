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
var client_input
var client_combat
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
	client_combat = preload("res://scripts/client_combat.gd").new()
	client_combat.game = self
	client_input = preload("res://scripts/client_input.gd").new()
	client_input.game = self
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
	client_input._move_local(delta)


func _unhandled_input(event: InputEvent) -> void:
	client_input._unhandled_input(event)


# ---------- действия игрока (уходят хосту) ----------

func _to_host(method: StringName, args: Array = []) -> void:
	if is_host:
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


var dash_charges := preload("res://scripts/dash_charges.gd").new()
const GiftMotion := preload("res://scripts/player_gift_motion.gd")


func dash() -> void:
	client_input.dash()


func attack() -> void:
	client_input.attack()


var parry_ready_at := 0

## Парирование (ПКМ / F): тратит выносливость, само окно и исход решает хост.
func parry() -> void:
	client_input.parry()


@rpc("any_peer", "call_remote", "reliable")
func h_parry() -> void:
	if host: host.parry()

@rpc("authority", "call_remote", "reliable")
func c_parry(pid: int) -> void:
	client_combat.c_parry(pid)

## Удачное парирование: искры, звон, надпись. Себе — сразу снова готово.
@rpc("authority", "call_remote", "reliable")
func c_parried(pid: int, enemy_pos: Vector2) -> void:
	client_combat.c_parried(pid, enemy_pos)


func move_mult() -> float:
	return client_input.move_mult()


## Запрос умения с панели.
func use_skill(id: String) -> void:
	client_input.use_skill(id)


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
	if me.is_empty() or int(me.hp) <= 0:
		return
	if interact.focused < 0:
		adventure("field")
		return
	var sp: Dictionary = interact.spot(interact.focused)
	if Vector2(sp.x, sp.y).distance_to(my_pos) > 70.0:
		ui.add_feed("Подойди ближе.", GREY)
		return
	if sp.kind == "adventure":
		if sp.action == "workshop":
			ui.adventure_panel.show_page(true)
		else:
			adventure("spot", sp.id)
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
		if loot_views[lid].position.distance_to(my_pos) > PICKUP_RADIUS * Rules.Gifts.factor(me, "pickup"):
			continue
		if me.inv.size() >= Items.bag_capacity(me) and not Items.is_stack(loot_views[lid].item) and loot_views[lid].item.base != "coins":
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
	if host: host.trader.trade_request(target)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_answer(from: int, accept: bool) -> void:
	if host: host.trader.trade_answer(from, accept)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_offer(uids: Array) -> void:
	if host: host.trader.trade_offer(uids)

@rpc("any_peer", "call_remote", "reliable")
func h_trade_confirm() -> void:
	if host: host.trader.trade_confirm()

@rpc("any_peer", "call_remote", "reliable")
func h_trade_cancel() -> void:
	if host: host.trader.trade_cancel()

@rpc("any_peer", "call_remote", "reliable")
func h_dash(dir: Vector2) -> void:
	if host: host.dash(dir)

@rpc("authority", "call_remote", "reliable")
func c_dash(pid: int) -> void:
	client_combat.c_dash(pid)

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
	client_combat.c_skill_fx(pid, id, dir)

## Ресурс класса (мана / ярость / энергия) — шлётся чаще, чем всё остальное о себе.
@rpc("authority", "call_remote", "unreliable_ordered")
func c_res(value: int, max_value: int) -> void:
	client_combat.c_res(value, max_value)


## Видимый снаряд (стрела, шар, луч). Попадание уже посчитано хостом.
@rpc("authority", "call_remote", "reliable")
func c_shot(from: Vector2, to: Vector2, kind: String, boom: float) -> void:
	client_combat.c_shot(from, to, kind, boom)

@rpc("authority", "call_remote", "reliable")
func c_levelup(pid: int, level: int) -> void:
	client_combat.c_levelup(pid, level)

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
		"cls": me.get("cls", "warrior"), "gifts": me.get("gifts", []), "gift_state": me.get("gift_state", {}), "materials": me.get("materials", {}), "professions": me.get("professions", {}),
		"tools": me.get("tools", {}), "visited": me.get("visited", {}), "cross_skill": me.get("cross_skill", "")})


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
	client_combat.c_enemy_spawn(d)


@rpc("authority", "call_remote", "reliable")
func c_enemy_hit(eid: int, hp: int, dmg: int, crit: bool) -> void:
	client_combat.c_enemy_hit(eid, hp, dmg, crit)


@rpc("authority", "call_remote", "reliable")
func c_enemy_died(eid: int) -> void:
	client_combat.c_enemy_died(eid)


@rpc("authority", "call_remote", "reliable")
func c_swing(pid: int, dir: Vector2) -> void:
	client_combat.c_swing(pid, dir)


@rpc("authority", "call_remote", "reliable")
func c_hp(pid: int, hp: int, max_hp: int, dealt: int) -> void:
	client_combat.c_hp(pid, hp, max_hp, dealt)


@rpc("authority", "call_remote", "reliable")
func c_teleport(pos: Vector2, blink: bool) -> void:
	client_combat.c_teleport(pos, blink)


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
	client_combat.float_text(pos, text, color)


## Хост обновил запас щита владельца.
@rpc("authority", "call_remote", "reliable")
func c_shield(amount: int) -> void:
	client_combat.c_shield(amount)


## Хост обновил параметры движения владельца.
@rpc("authority", "call_remote", "reliable")
func c_gift_motion(values: Dictionary) -> void:
	client_combat.c_gift_motion(values)


## Дар сбросил перезарядку удачного парирования.
@rpc("authority", "call_remote", "reliable")
func c_parry_reset() -> void:
	client_combat.c_parry_reset()


var stun_local_until := 0
var slow_local_until := 0
var adventure_marks := {}


## Посылает запрос на действие в мире.
func adventure(op: String, arg: String = "") -> void:
	_to_host("h_adventure", [op, arg])


@rpc("any_peer", "call_remote", "reliable")
func h_adventure(op: String, arg: String) -> void:
	if host:
		host.adventure(op, arg)


@rpc("authority", "call_remote", "reliable")
func c_adventure_control(stun: bool, seconds: float) -> void:
	var until := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	if stun:
		stun_local_until = until
		dash_left = 0.0
	else:
		slow_local_until = until


@rpc("authority", "call_remote", "reliable")
func c_adventure_mark(id: String, pos: Vector2, show_mark: bool) -> void:
	if show_mark:
		adventure_marks[id] = pos
	else:
		adventure_marks.erase(id)


@rpc("authority", "call_remote", "reliable")
func c_world_pulse(pos: Vector2, radius: float, color: Color) -> void:
	fx.burst(pos, color, clampi(roundi(radius * 0.4), 5, 36), radius > 40.0)


@rpc("authority", "call_remote", "reliable")
func c_enemy_elite(eid: int, hp: int, maximum: int) -> void:
	client_combat.c_enemy_elite(eid, hp, maximum)


@rpc("authority", "call_remote", "reliable")
func c_dash_reset() -> void:
	client_combat.c_dash_reset()


## Показывает полупрозрачный силуэт на месте рывка.
@rpc("authority", "call_remote", "reliable")
func c_adventure_decoy(pid: int, pos: Vector2, duration: float) -> void:
	var source = player_views.get(pid)
	if source == null:
		return
	var image := PlayerView.new()
	image.equip = source.equip
	image.look = source.look
	image.pname = "Копия"
	image.npc = true
	image.position = pos
	image.target = pos
	image.facing = source.facing
	image.modulate = Color(0.55, 0.76, 1.0, 0.58)
	entities.add_child(image)
	get_tree().create_timer(duration).timeout.connect(image.queue_free)
