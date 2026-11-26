extends RefCounted
## Создание клиентского мира и обновление его узлов.

const Ground := preload("res://scripts/ground.gd")

const Fx := preload("res://scripts/fx.gd")

const GameUI := preload("res://scripts/ui.gd")

const HostLogic := preload("res://scripts/host_logic.gd")

const PropsLayer := preload("res://scripts/props_layer.gd")

const Ambience := preload("res://scripts/ambience.gd")

const Interact := preload("res://scripts/interact.gd")

var game


func start() -> void:
	randomize()
	game.is_host = game.multiplayer.is_server()
	game.my_id = game.multiplayer.get_unique_id()
	game.WORLD_SIZE = World.size
	game.SPAWN = World.spawn
	game.my_pos = game.SPAWN
	game.add_child(Ground.new())
	var shadows := Node2D.new()      # тени объектов — под всеми, кто стоит на земле
	game.add_child(shadows)
	game.entities = Node2D.new()
	game.entities.y_sort_enabled = true
	game.add_child(game.entities)
	var pl = PropsLayer.new()
	game.add_child(pl)
	pl.populate(game.entities, shadows)
	var amb = Ambience.new()
	amb.game = game
	game.add_child(amb)
	amb.build(game.entities)
	game.interact = Interact.new()
	game.interact.game = game
	game.add_child(game.interact)
	var aim = preload("res://scripts/aim_overlay.gd").new()      # прицел своего героя
	aim.game = game
	game.add_child(aim)
	game.camera = Camera2D.new()
	game.camera.limit_right = int(game.WORLD_SIZE.x)
	game.camera.limit_bottom = int(game.WORLD_SIZE.y)
	game.camera.limit_left = 0
	game.camera.limit_top = 0
	game.camera.position = game.SPAWN
	game.add_child(game.camera)
	game.fx = Fx.new()
	game.fx.game = game
	game.add_child(game.fx)
	game.ui = GameUI.new()
	game.ui.game = game
	game.add_child(game.ui)
	game.multiplayer.server_disconnected.connect(_on_server_disconnected)
	var char_data := Save.load_char(Net.player_name, Net.player_class, Net.player_gifts)
	if not Net.player_look.is_empty():
		char_data.look = Net.player_look
	if game.is_host:
		game.host = HostLogic.new()
		game.host.game = game
		game.add_child(game.host)
		game.multiplayer.peer_disconnected.connect(game.host.on_peer_disconnected)
		game.h_register(char_data)
		game.host.start_world()
		game.ui.add_feed("Мир создан на порту %d. Друзья подключаются по твоему IP." % Net.port, Color(0.7, 0.9, 1.0))
	else:
		game.rpc_id(1, "h_register", char_data)
	game.ui.add_feed("WASD — ходьба · Shift — бег · Пробел — рывок · ЛКМ — удар · ПКМ/F — парирование · E — взаимодействие · I — сумка", game.GREY)
	game.ui.add_feed("1 2 3 4 — умения класса (открываются с уровнем) · C — герой, класс и дары", game.GREY)
	_maybe_autotest()


func _process(delta: float) -> void:
	game.client_input._move_local(delta)
	if game.open_spot >= 0 and game.ui.shop.mode != "":           # отошёл — окно закрывается
		var sp: Dictionary = game.interact.spot(game.open_spot)
		if Vector2(sp.x, sp.y).distance_to(game.my_pos) > 90.0:
			game.ui.shop.close_all()
			game.open_spot = -1
	game.camera.position = game.my_pos
	game.client_inventory._auto_pickup()


func _maybe_autotest() -> void:
	if not OS.is_debug_build():
		return
	var args := OS.get_cmdline_user_args()
	if not args.has("--autotest"):
		return
	var tester = load("res://scripts/debug_autotest.gd").new()
	tester.game = game
	for a in args:
		if a.begins_with("--shots="):
			tester.shots_dir = a.trim_prefix("--shots=")
	game.add_child(tester)


func leave_game() -> void:
	Net.leave()
	game.get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_server_disconnected() -> void:
	Net.last_error = "Хост закрыл мир или связь потеряна."
	game.leave_game()
