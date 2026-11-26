extends Control
## Главное меню: создать мир или подключиться к другу.
## Для тестов можно запускать с аргументами:  -- --host --name=Аня   или   -- --join=127.0.0.1 --name=Боря

const GAME_SCENE := "res://scenes/game.tscn"

var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit
var status: Label


const Kit := preload("res://scripts/ui_kit.gd")
const BACKDROP := preload("res://assets/custom/world/menu_bg.png")
const CharBaker := preload("res://scripts/char_baker.gd")
const DollView := preload("res://scripts/doll_view.gd")
const NAMES := {"human": "человек", "elf": "эльф", "dwarf": "дварф", "orc": "орк", "undead": "нежить", "felin": "кошколюд",
	"goblin": "гоблин", "m": "мужской", "f": "женский",
	"pale": "бледная", "green": "зелёная", "olive": "оливковая", "moss": "болотная", "ash": "пепельная", "bluish": "синеватая",
	"lime": "салатовая", "khaki": "хаки", "greygreen": "серо-зелёная",
	"light": "светлая", "mid": "смуглая", "dark": "тёмная", "short": "короткая", "long": "длинная",
	"tail": "хвост", "spiky": "торчком", "braid": "коса", "bob": "каре", "bun": "пучок",
	"brown": "каштан", "black": "чёрный", "blond": "блонд", "red": "рыжий", "white": "седой",
	"none": "нет", "full": "густая", "moustache": "усы", "stubble": "щетина",
	"scar": "шрам", "freckles": "веснушки", "warpaint": "раскраска"}
const EYE_NAMES := {"brown": "карие", "blue": "голубые", "green": "зелёные", "grey": "серые", "amber": "янтарные"}

var look := {}
var doll
var look_labels := {}
var race_info: Label


func _ready() -> void:
	theme = Kit.make_theme()
	# фон: кусок карты с городом, затемнённый
	var bg := TextureRect.new()
	bg.texture = BACKDROP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.03, 0.07, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)
	var logo := Kit.label("ОСКОЛКИ УДАЧИ", 36, Kit.GOLD)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_constant_override("shadow_offset_x", 2)
	logo.add_theme_constant_override("shadow_offset_y", 2)
	col.add_child(logo)
	var tag := Kit.label("кооперативная RPG · до 8 героев · мега-редкий лут", 9, Kit.DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var row_main := HBoxContainer.new()
	row_main.add_theme_constant_override("separation", 6)
	col.add_child(row_main)
	_build_look(row_main)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 0)
	row_main.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var saved_name := Save.load_last_name()
	name_edit = _field(box, "Имя героя", saved_name if saved_name != "" else "Герой%d" % (randi() % 900 + 100))
	box.add_child(Kit.button("Создать мир  (ты — хост)", _on_host))
	box.add_child(Kit.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	var ipb := VBoxContainer.new()
	ipb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ipb)
	ip_edit = _field(ipb, "IP хоста", "127.0.0.1")
	var pb := VBoxContainer.new()
	pb.custom_minimum_size = Vector2(56, 0)
	row.add_child(pb)
	port_edit = _field(pb, "Порт", str(Net.DEFAULT_PORT))
	box.add_child(Kit.button("Подключиться к миру", _on_join))

	status = Kit.label(Net.last_error, 9, Kit.RED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	Net.last_error = ""

	var hint := Kit.label("По интернету: хост открывает порт 7777 (UDP) или все ставят Radmin VPN / ZeroTier. " +
		"В одной Wi-Fi сети — подключайтесь по локальному IP.", 9, Kit.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(230, 0)
	col.add_child(hint)

	_apply_cmdline_args()


func _build_look(parent: Control) -> void:
	look = CharBaker.sanitize_look(Save.load_look())
	var p := PanelContainer.new()
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var t := Kit.label("Создание героя", 9, Kit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(110, 84)
	v.add_child(holder)
	var box := Control.new()
	box.custom_minimum_size = Vector2(64, 64)
	holder.add_child(box)
	doll = DollView.new()
	box.add_child(doll)
	CharBaker._load_meta()
	var m: Dictionary = CharBaker.meta
	for key in [["race", "Раса", m.races.keys()], ["sex", "Пол", ["m", "f"]], ["skin", "Кожа", []],
			["hair", "Причёска", m.hair_styles], ["hair_color", "Волосы", m.hair_colors],
			["eyes", "Глаза", CharBaker.EYES.keys()], ["beard", "Борода", ["none"] + m.beards],
			["marks", "Отметины", ["none"] + m.marks]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 2)
		v.add_child(h)
		var cap := Kit.label(key[1], 9, Kit.DIM)
		cap.custom_minimum_size = Vector2(46, 0)
		h.add_child(cap)
		h.add_child(Kit.button("<", _cycle.bind(key[0], key[2], -1)))
		var l := Kit.label("", 9)
		l.custom_minimum_size = Vector2(66, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(l)
		look_labels[key[0]] = l
		h.add_child(Kit.button(">", _cycle.bind(key[0], key[2], 1)))
	v.add_child(Kit.divider())
	race_info = Kit.label("", 9, Color(0.6, 0.9, 0.6))
	race_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	race_info.custom_minimum_size = Vector2(150, 0)
	v.add_child(race_info)
	_apply_look()


func _cycle(key: String, options: Array, dir: int) -> void:
	if key == "skin":                         # тона кожи зависят от расы
		options = CharBaker.meta.races[look.race].tones
	if key == "beard" and look.race == "dwarf":
		options = CharBaker.meta.beards        # дварф без бороды не бывает
	var i := options.find(look[key])
	look[key] = options[(i + dir + options.size()) % options.size()]
	look = CharBaker.sanitize_look(look)
	_apply_look()


func _apply_look() -> void:
	for k in look_labels:
		look_labels[k].text = EYE_NAMES[look[k]] if k == "eyes" else NAMES.get(look[k], look[k])
		look_labels[k].modulate.a = 0.35 if k == "beard" and look.sex == "f" else 1.0
	var r: Dictionary = Rules.RACES[look.race]
	var st := []
	for s in r.stats:
		st.append("%s +%d" % [Rules.STAT_NAMES[s], r.stats[s]])
	race_info.text = "%s\n%s\nУмение: %s" % [", ".join(st), r.passive, Rules.SKILLS[r.skill].name]
	race_info.tooltip_text = Rules.SKILLS[r.skill].desc
	doll.look = look
	doll.equip = {"weapon": {"base": "sword", "rarity": 0, "shiny": false}}
	Save.store_look(look)
	Net.player_look = look


func _field(parent: Control, caption: String, value: String) -> LineEdit:
	parent.add_child(Kit.label(caption, 9, Kit.DIM))
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(0, 15)
	parent.add_child(e)
	return e

func _player_name() -> String:
	var n := name_edit.text.strip_edges().left(16)
	if n == "":
		n = "Герой"
	Save.store_last_name(n)
	return n


func _on_host() -> void:
	Net.player_name = _player_name()
	var err := Net.host(int(port_edit.text))
	if err != OK:
		status.text = "Не удалось создать мир (порт %s занят?). Код ошибки %d" % [port_edit.text, err]
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_join() -> void:
	Net.player_name = _player_name()
	var err := Net.join(ip_edit.text.strip_edges(), int(port_edit.text))
	if err != OK:
		status.text = "Ошибка подключения, код %d" % err
		return
	status.text = "Подключаемся к %s…" % ip_edit.text
	multiplayer.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)


func _on_connected() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_failed() -> void:
	Net.leave()
	status.text = "Не удалось подключиться. Проверь IP, порт и что хост запущен."


func _apply_cmdline_args() -> void:
	if Net.args_applied:
		if OS.get_cmdline_user_args().has("--autotest"):
			get_tree().quit()    # автотест не должен оставлять открытые окна
		return
	Net.args_applied = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.has("winsize"):
		var s: PackedStringArray = args.winsize.split("x")
		DisplayServer.window_set_size(Vector2i(int(s[0]), int(s[1])))
	if args.has("winpos"):
		var p: PackedStringArray = args.winpos.split(",")
		DisplayServer.window_set_position(Vector2i(int(p[0]), int(p[1])))
	if args.has("look"):
		var lp: PackedStringArray = args.look.split(",")
		var keys := ["race", "skin", "hair", "hair_color", "sex", "eyes", "beard", "marks"]
		var d := {}
		for k in mini(lp.size(), keys.size()):
			d[keys[k]] = lp[k]
		look = CharBaker.sanitize_look(d)
		_apply_look()
	if args.has("menushot") and OS.is_debug_build():
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(args.menushot)
		get_tree().quit()
		return
	if args.has("name"):
		name_edit.text = args.name
	if args.has("host"):
		_on_host.call_deferred()
	elif args.has("join"):
		if args.join != "true":
			ip_edit.text = args.join
		_on_join.call_deferred()
