extends Node2D
## Мир игры. Хост (peer 1) — единственный, кто решает: бой, лут, инвентари, обмены.
## Клиенты шлют хосту намерения (h_*), хост рассылает результаты (c_*).
## Поэтому этот же код потом можно запустить как выделенный сервер.

var client_input
var client_combat
var client_inventory
var client_adventure
var client_session
var client_world
var client_market
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
var stamina := 100.0
var dash_left := 0.0
var dash_dir := Vector2.ZERO
const DASH_SPEED := 3.3

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
	client_world = preload("res://scripts/client_world.gd").new()
	client_world.game = self
	client_market = preload("res://scripts/client_market.gd").new()
	client_market.game = self
	client_world.start()

func _process(delta: float) -> void:
	client_world._process(delta)

func _unhandled_input(event: InputEvent) -> void:
	client_input._unhandled_input(event)

# ---------- действия игрока (уходят хосту) ----------

func _to_host(method: StringName, args: Array = []) -> void:
	if is_host:
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)

func dash() -> void:
	client_input.dash()

func attack() -> void:
	client_input.attack()

func parry() -> void:
	client_input.parry()

@rpc("any_peer", "call_remote", "reliable")
func h_parry() -> void:
	if host: host.parry()

@rpc("authority", "call_remote", "reliable")
func c_parry(pid: int) -> void:
	client_combat.c_parry(pid)

@rpc("authority", "call_remote", "reliable")
func c_parried(pid: int, enemy_pos: Vector2) -> void:
	client_combat.c_parried(pid, enemy_pos)

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

func use_spot() -> void:
	client_adventure.use_spot()

func eco(op: String, arg := "") -> void:
	client_inventory.eco(op, arg)

func send_chat(text: String) -> void:
	_to_host("h_chat", [text])

func leave_game() -> void:
	client_world.leave_game()

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

@rpc("authority", "call_remote", "unreliable_ordered")
func c_res(value: int, max_value: int) -> void:
	client_combat.c_res(value, max_value)

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

@rpc("authority", "call_remote", "reliable")
func c_shield(amount: int) -> void:
	client_combat.c_shield(amount)

@rpc("authority", "call_remote", "reliable")
func c_gift_motion(values: Dictionary) -> void:
	client_combat.c_gift_motion(values)

@rpc("authority", "call_remote", "reliable")
func c_parry_reset() -> void:
	client_combat.c_parry_reset()

var adventure_marks := {}

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

@rpc("authority", "call_remote", "reliable")
func c_adventure_decoy(pid: int, pos: Vector2, duration: float) -> void:
	client_adventure.c_adventure_decoy(pid, pos, duration)


## Запрос к рынку проверяет только хост.
@rpc("any_peer", "call_remote", "reliable")
func h_market(op: String, arg: Dictionary) -> void:
	if host: host.market.handle(op, arg)


## Результат поиска или сделки получает владелец окна.
@rpc("authority", "call_remote", "reliable")
func c_market(data: Dictionary) -> void:
	client_market.receive(data)
