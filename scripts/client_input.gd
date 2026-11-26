extends RefCounted
## Ввод, движение и локальные проверки действий игрока.

const GiftMotion := preload("res://scripts/player_gift_motion.gd")

var game
const ATTACK_CD := {"slash": 340, "chop": 520, "stab": 220, "bolt": 560, "shot": 500}
const DASH_COST := 30.0
const SPRINT := 1.55
var slow_local_until := 0
var stun_local_until := 0
var dash_charges := preload("res://scripts/dash_charges.gd").new()
var parry_ready_at := 0
var dust_acc := 0.0
var stamina_idle := 0.0
var step_acc := 0.0
var last_attack := 0
var send_acc := 0.0
var aiming := ""                 # умение, которое сейчас прицеливается (клавиша зажата)
var aiming_key := 0
const SKILL_KEYS := {KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4}


func _move_local(delta: float) -> void:
	if game.me.is_empty() or int(game.me.hp) <= 0 or game.ui.is_typing() or Time.get_ticks_msec() < stun_local_until:
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
	var sprint: bool = Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector2.ZERO and (game.stamina > 1.0 or GiftMotion.sprint_cost(game.me) == 0.0)
	if game.dash_left > 0.0:                                  # рывок: летим по направлению, ввод игнорируется
		game.dash_left -= delta
		game.my_pos = World.move(game.my_pos, game.dash_dir * game.SPEED * game.DASH_SPEED * Rules.Gifts.factor(game.me, "dash_dist") * delta)
	elif dir != Vector2.ZERO:
		game.my_pos = World.move(game.my_pos, dir.normalized() * game.SPEED * move_mult() * (SPRINT * Rules.Gifts.factor(game.me, "sprint_speed") if sprint else 1.0) * delta)
		step_acc += delta * (1.5 if sprint else 1.0)
		if step_acc > 0.3:
			step_acc = 0.0
			Sfx.play("step")
	if sprint and game.dash_left <= 0.0:
		game.stamina = maxf(0.0, game.stamina - GiftMotion.sprint_cost(game.me) * delta)
		stamina_idle = 0.0
		dust_acc += delta
		if dust_acc > 0.12:
			dust_acc = 0.0
			game.fx.dust(game.my_pos)
	else:
		stamina_idle += delta
		if stamina_idle > 0.6:
			game.stamina = minf(100.0, game.stamina + 24.0 * GiftMotion.stamina_regen(game.me) * delta)
	game.ui.hud.set_stamina(game.stamina / 100.0)
	var aim = aim_vector()
	if aim.length() > 6.0:
		game.my_facing = aim.normalized()
	var view = game.player_views.get(game.my_id)
	if view:
		view.position = game.my_pos
		view.target = game.my_pos
		view.facing = game.my_facing
	send_acc += delta
	if send_acc >= game.NET_TICK and not game.is_host:
		send_acc = 0.0
		game.rpc_id(1, "h_pos", game.my_pos, game.my_facing)


## Нужно ли умению прицеливание: снаряды, удары по точке и лечение союзника.
func needs_aim(id: String) -> bool:
	var sk: Dictionary = Rules.SKILLS.get(id, {})
	return str(sk.get("kind", "")) in ["bolt", "multi"] or sk.has("ground") or str(sk.get("target", "")) == "lowest"


## Вектор от героя к курсору — куда целится игрок.
var aim_override := Vector2.ZERO   # автотест: прицел без мыши

func aim_vector() -> Vector2:
	if aim_override != Vector2.ZERO:
		return aim_override
	return game.get_global_mouse_position() - game.my_pos


func _unhandled_input(event: InputEvent) -> void:
	# прицеливание: зажал клавишу умения — видна зона, отпустил — умение срабатывает; ПКМ/Esc — отмена
	if aiming != "" and event is InputEventKey and not event.pressed and event.physical_keycode == aiming_key:
		var id := aiming
		aiming = ""
		game.use_skill(id)
		return
	if aiming != "" and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
			or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE)):
		aiming = ""
		game.get_viewport().set_input_as_handled()
		return
	if aiming != "" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := aiming                          # ЛКМ во время прицела — тоже применить
		aiming = ""
		game.use_skill(id)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sp: Dictionary = game.interact.spot(game.interact.focused) if game.interact.focused >= 0 else {}
		var aim = game.get_global_mouse_position()
		if not sp.is_empty() and aim.distance_to(Vector2(sp.x, sp.y) - Vector2(0, float(sp.h) * 0.5)) < 14.0:
			game.use_spot()
		else:
			game.attack()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		game.parry()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				game.dash()
			KEY_F:
				game.parry()
			KEY_I, KEY_TAB:
				game.ui.toggle_inventory()
			KEY_T:
				game.request_trade_nearest()
			KEY_E:
				game.use_spot()
			KEY_C:
				game.ui.charwin.toggle()
			KEY_J:
				game.ui.adventure_panel.show_page(false)
			KEY_R:
				game.adventure("rescue")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var ids: Array = game.ui.hud.skills.ids
				var i: int = SKILL_KEYS[event.physical_keycode]
				if i < ids.size():
					if needs_aim(ids[i]) and Rules.skill_unlocked(game.me, ids[i]):
						aiming = ids[i]
						aiming_key = event.physical_keycode
					else:
						game.use_skill(ids[i])
			KEY_ENTER, KEY_KP_ENTER:
				game.ui.open_chat()
				game.get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				game.ui.close_panels()
			KEY_F9:
				if game.is_host and OS.is_debug_build():
					game.host.debug_jackpot()


func dash() -> void:
	var free: bool = not game.me.is_empty() and game.ui.hud.skills.has_buff("pounce")     # кошачья прыть: рывки бесплатно
	if game.me.is_empty() or int(game.me.hp) <= 0 or game.dash_left > 0.0 or (game.stamina < DASH_COST and not free):
		return
	if not dash_charges.consume(game.me, free):
		return
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1
	game.dash_dir = dir.normalized() if dir != Vector2.ZERO else game.my_facing
	game.dash_left = 0.0 if Rules.Gifts.has_flag(game.me, "blink_dash") else 0.2
	if not free:
		game.stamina -= DASH_COST
	stamina_idle = 0.0
	game.fx.dust(game.my_pos, 10)
	Sfx.play("swing", -2.0, 0.7)
	game._to_host("h_dash", [game.dash_dir])


func attack() -> void:
	if game.me.is_empty() or int(game.me.hp) <= 0:
		return
	var now := Time.get_ticks_msec()
	var style: String = "stab" if not game.me.equip.has("weapon") and Rules.Gifts.has_flag(game.me, "fists") else Items.style_of(game.me.equip.get("weapon"))
	if now - last_attack < int(float(ATTACK_CD[style]) / GiftMotion.attack_speed(game.me, game.ui.hud)):
		return
	last_attack = now
	game._to_host("h_attack", [game.my_facing])


func parry() -> void:
	if game.me.is_empty() or int(game.me.hp) <= 0:
		return
	if not Rules.can_parry(game.me):
		game.ui.add_feed("Парировать можно только оружием ближнего боя.", game.GREY)
		return
	var now := Time.get_ticks_msec()
	var cost = Rules.PARRY.cost * Rules.Gifts.factor(game.me, "parry_cost")
	if now < parry_ready_at or game.stamina < cost:
		return
	parry_ready_at = now + int(Rules.PARRY.cd * 1000.0)
	game.stamina -= cost
	stamina_idle = 0.0
	game._to_host("h_parry")


func move_mult() -> float:
	if game.me.is_empty():
		return 1.0
	return GiftMotion.speed(game.me, game.ui.hud) * GiftMotion.terrain(game.me, game.my_pos, Time.get_ticks_msec() < slow_local_until)


func use_skill(id: String) -> void:
	if game.me.is_empty() or int(game.me.hp) <= 0:
		return
	var bar = game.ui.hud.skills
	if not Rules.skill_unlocked(game.me, id):
		game.ui.add_feed("%s откроется на %d уровне." % [Rules.SKILLS[id].name, Rules.skill_level(game.me, id)], game.GREY)
		return
	if not Rules.has_class_weapon(game.me):
		var names := PackedStringArray()
		for b in Rules.class_of(game.me).weapons:
			names.append(Items.BASES[b].name.to_lower())
		game.ui.add_feed("Умения класса работают только со своим оружием: %s." % ", ".join(names), game.GREY)
		return
	if bar.cd_left(id) > 0.0:
		return
	var hp_cost = Rules.res_kind(game.me) == "mana" and Rules.Gifts.has_flag(game.me, "hp_cost")
	var available = int(game.me.hp) - 1 if hp_cost else int(game.me.get("res", 0))
	if available < Rules.skill_cost(game.me, id):
		game.ui.add_feed("Не хватает: %s." % Rules.RES_NAMES[Rules.res_kind(game.me)].to_lower(), game.GREY)
		return
	bar.start_cd(id)
	var aim := aim_vector()
	if aim.length() > 6.0:
		game.my_facing = aim.normalized()
	else:
		aim = game.my_facing
	game._to_host("h_skill", [id, aim])
