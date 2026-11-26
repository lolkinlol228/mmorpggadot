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
var client_inventory
var client_adventure
var client_session
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
	client_session = preload("res://scripts/client_session.gd").new()
	client_session.game = self
	client_adventure = preload("res://scripts/client_adventure.gd").new()
	client_adventure.game = self
	client_inventory = preload("res://scripts/client_inventory.gd").new()
	client_inventory.game = self
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
	client_inventory.request_equip(uid)


func request_unequip(slot: String) -> void:
	client_inventory.request_unequip(slot)


func request_trade_nearest() -> void:
	client_inventory.request_trade_nearest()


func answer_trade(from: int, accept: bool) -> void:
	client_inventory.answer_trade(from, accept)


func send_trade_offer(uids: Array) -> void:
	client_inventory.send_trade_offer(uids)


func confirm_trade() -> void:
	client_inventory.confirm_trade()


func cancel_trade() -> void:
	client_inventory.cancel_trade()


## Взаимодействие с отмеченным объектом (хранилище, лавка, доска, житель).
func use_spot() -> void:
	client_adventure.use_spot()


func eco(op: String, arg := "") -> void:
	client_inventory.eco(op, arg)


func send_chat(text: String) -> void:
	_to_host("h_chat", [text])


func leave_game() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _auto_pickup() -> void:
	client_inventory._auto_pickup()


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
	client_session.c_init(ps, es, ls, priv)


@rpc("authority", "call_remote", "reliable")
func c_self(priv: Dictionary) -> void:
	client_session.c_self(priv)


@rpc("authority", "call_remote", "reliable")
func c_player_joined(pub: Dictionary) -> void:
	client_session.c_player_joined(pub)


@rpc("authority", "call_remote", "reliable")
func c_player_left(pid: int) -> void:
	client_session.c_player_left(pid)


@rpc("authority", "call_remote", "unreliable_ordered")
func c_state(ps: Array, es: Array) -> void:
	client_session.c_state(ps, es)


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
	client_inventory.c_equip(pid, equip)


@rpc("authority", "call_remote", "reliable")
func c_loot(lid: int, item: Dictionary, pos: Vector2) -> void:
	client_inventory.c_loot(lid, item, pos)


func _add_loot(lid: int, item: Dictionary, pos: Vector2, fresh: bool) -> void:
	client_inventory._add_loot(lid, item, pos, fresh)


@rpc("authority", "call_remote", "reliable")
func c_loot_gone(lid: int) -> void:
	client_inventory.c_loot_gone(lid)


@rpc("authority", "call_remote", "reliable")
func c_jackpot(finder: String, item: Dictionary) -> void:
	client_inventory.c_jackpot(finder, item)


@rpc("authority", "call_remote", "reliable")
func c_chat(from: String, text: String) -> void:
	client_session.c_chat(from, text)


@rpc("authority", "call_remote", "reliable")
func c_announce(text: String, color: Color) -> void:
	client_session.c_announce(text, color)


@rpc("authority", "call_remote", "reliable")
func c_trade_invite(from: int, from_name: String) -> void:
	client_inventory.c_trade_invite(from, from_name)


@rpc("authority", "call_remote", "reliable")
func c_trade_open(other_name: String) -> void:
	client_inventory.c_trade_open(other_name)


@rpc("authority", "call_remote", "reliable")
func c_trade_state(mine: Array, theirs: Array, my_ok: bool, their_ok: bool) -> void:
	client_inventory.c_trade_state(mine, theirs, my_ok, their_ok)


@rpc("authority", "call_remote", "reliable")
func c_trade_closed(msg: String) -> void:
	client_inventory.c_trade_closed(msg)


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
	client_adventure.adventure(op, arg)


@rpc("any_peer", "call_remote", "reliable")
func h_adventure(op: String, arg: String) -> void:
	if host:
		host.adventure(op, arg)


@rpc("authority", "call_remote", "reliable")
func c_adventure_control(stun: bool, seconds: float) -> void:
	client_adventure.c_adventure_control(stun, seconds)


@rpc("authority", "call_remote", "reliable")
func c_adventure_mark(id: String, pos: Vector2, show_mark: bool) -> void:
	client_adventure.c_adventure_mark(id, pos, show_mark)


@rpc("authority", "call_remote", "reliable")
func c_world_pulse(pos: Vector2, radius: float, color: Color) -> void:
	client_adventure.c_world_pulse(pos, radius, color)


@rpc("authority", "call_remote", "reliable")
func c_enemy_elite(eid: int, hp: int, maximum: int) -> void:
	client_combat.c_enemy_elite(eid, hp, maximum)


@rpc("authority", "call_remote", "reliable")
func c_dash_reset() -> void:
	client_combat.c_dash_reset()


## Показывает полупрозрачный силуэт на месте рывка.
@rpc("authority", "call_remote", "reliable")
func c_adventure_decoy(pid: int, pos: Vector2, duration: float) -> void:
	client_adventure.c_adventure_decoy(pid, pos, duration)
