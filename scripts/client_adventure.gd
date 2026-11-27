extends RefCounted
## Взаимодействия, приключения и ремёсла на клиенте.

const PlayerView := preload("res://scripts/player_view.gd")

var game


func use_spot() -> void:
	if game.me.is_empty() or int(game.me.hp) <= 0:
		return
	if game.interact.focused < 0:
		game.adventure("field")
		return
	var sp: Dictionary = game.interact.spot(game.interact.focused)
	if Vector2(sp.x, sp.y).distance_to(game.my_pos) > 70.0:
		game.ui.add_feed("Подойди ближе.", game.GREY)
		return
	if sp.kind == "mine":
		game.adventure("mine", sp.action)
		return
	if sp.has("actor"):
		game.adventure("talk", sp.actor)
	if sp.kind == "adventure":
		if sp.action == "workshop":
			game.ui.adventure_panel.show_page(true)
		else:
			game.adventure("spot", sp.id)
		return
	game.open_spot = game.interact.focused
	if game.player_views.has(game.my_id):
		game.player_views[game.my_id].use()
	game.ui.shop.open(sp.kind, sp)


func adventure(op: String, arg: String = "") -> void:
	game._to_host("h_adventure", [op, arg])


func c_adventure_control(stun: bool, seconds: float) -> void:
	var until := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	if stun:
		game.client_input.stun_local_until = until
		game.dash_left = 0.0
	else:
		game.client_input.slow_local_until = until


func c_adventure_mark(id: String, pos: Vector2, show_mark: bool) -> void:
	if show_mark:
		game.adventure_marks[id] = pos
	else:
		game.adventure_marks.erase(id)


func c_world_pulse(pos: Vector2, radius: float, color: Color) -> void:
	game.fx.burst(pos, color, clampi(roundi(radius * 0.4), 5, 36), radius > 40.0)


func c_adventure_decoy(pid: int, pos: Vector2, duration: float) -> void:
	var source = game.player_views.get(pid)
	if source == null:
		return
	var image = PlayerView.new()
	image.equip = source.equip
	image.look = source.look
	image.pname = "Копия"
	image.npc = true
	image.position = pos
	image.target = pos
	image.facing = source.facing
	image.modulate = Color(0.55, 0.76, 1.0, 0.58)
	game.entities.add_child(image)
	game.get_tree().create_timer(duration).timeout.connect(image.queue_free)
