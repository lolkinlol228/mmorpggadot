extends Control
## HUD: портрет и здоровье, мини-карта с названием зоны, чат, панель действий,
## баннер входа в зону, экран смерти.

const Kit := preload("res://scripts/ui_kit.gd")
const Minimap := preload("res://scripts/minimap.gd")
const ItemSlot := preload("res://scripts/item_slot.gd")
const CharBaker := preload("res://scripts/char_baker.gd")
const SkillBar := preload("res://scripts/skill_bar.gd")

var game
var ui
var hp_fill: TextureRect
var st_fill: ColorRect
var face: TextureRect
var face_tex := AtlasTexture.new()
var hp_text: Label
var coin_icons: Array = []
var coin_labels: Array = []
var zone_label: Label
var chat_log: RichTextLabel
var chat_input: LineEdit
var zone_banner: Label
var zone_sub: Label
var death: ColorRect
var current_zone := ""
var zone_acc := 0.0
var skills                   # панель умений
var lvl_label: Label
var xp_fill: ColorRect
var res_fill: ColorRect


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_portrait()
	_build_minimap()
	_build_chat()
	_build_actions()
	skills = SkillBar.new()
	skills.game = game
	add_child(skills)
	skills.build()
	_build_banner()
	_build_death()


func _build_portrait() -> void:
	var root := HBoxContainer.new()
	root.position = Vector2(6, 6)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	var frame := TextureRect.new()
	frame.texture = Kit.tex("portrait")
	frame.custom_minimum_size = Vector2(40, 40)
	root.add_child(frame)
	face = TextureRect.new()
	face_tex.atlas = CharBaker.bake({})
	face_tex.region = Rect2(16, 9, 16, 16)
	face.texture = face_tex
	face.position = Vector2(4, 4)
	face.size = Vector2(32, 32)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	root.add_child(v)
	v.add_child(Kit.label(Net.player_name + ("  · хост" if game.is_host else ""), 9, Kit.GOLD))
	var bar := NinePatchRect.new()
	bar.texture = Kit.tex("bar_frame")
	bar.patch_margin_left = 4
	bar.patch_margin_right = 4
	bar.patch_margin_top = 3
	bar.patch_margin_bottom = 3
	bar.custom_minimum_size = Vector2(110, 11)
	v.add_child(bar)
	hp_fill = TextureRect.new()
	hp_fill.texture = Kit.tex("bar_hp")
	hp_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_fill.stretch_mode = TextureRect.STRETCH_SCALE
	hp_fill.position = Vector2(2, 3)
	hp_fill.size = Vector2(106, 5)
	bar.add_child(hp_fill)
	var res_bg := ColorRect.new()                      # ресурс класса: мана / ярость / энергия
	res_bg.color = Color(0.05, 0.05, 0.07, 0.9)
	res_bg.custom_minimum_size = Vector2(110, 4)
	v.add_child(res_bg)
	res_fill = ColorRect.new()
	res_fill.size = Vector2(0, 4)
	res_bg.add_child(res_fill)
	var st_bg := ColorRect.new()                       # выносливость: бег и рывок
	st_bg.color = Color(0.05, 0.05, 0.07, 0.9)
	st_bg.custom_minimum_size = Vector2(110, 3)
	v.add_child(st_bg)
	st_fill = ColorRect.new()
	st_fill.color = Color(0.85, 0.8, 0.3)
	st_fill.size = Vector2(110, 3)
	st_bg.add_child(st_fill)
	var xp_bg := ColorRect.new()                       # опыт до следующего уровня
	xp_bg.color = Color(0.05, 0.05, 0.07, 0.9)
	xp_bg.custom_minimum_size = Vector2(110, 2)
	v.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.5, 0.6, 1.0)
	xp_fill.size = Vector2(0, 2)
	xp_bg.add_child(xp_fill)
	lvl_label = Kit.label("1", 9, Color.WHITE)
	lvl_label.position = Vector2(1, 28)
	lvl_label.size = Vector2(12, 10)
	lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(lvl_label)
	hp_text = Kit.label("", 9)
	hp_text.position = Vector2(0, -3)
	hp_text.size = Vector2(110, 11)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(hp_text)
	var gh := HBoxContainer.new()                     # кошелёк: платина, золото, серебро, медь
	gh.add_theme_constant_override("separation", 1)
	for d in 4:
		var ic := TextureRect.new()
		ic.texture = Items.coin_icon(d)
		ic.custom_minimum_size = Vector2(10, 10)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gh.add_child(ic)
		var l := Kit.label("0", 9, [Color(0.75, 0.92, 1.0), Kit.GOLD, Color(0.85, 0.87, 0.92), Color(0.9, 0.6, 0.4)][d])
		gh.add_child(l)
		coin_icons.append(ic)
		coin_labels.append(l)
	v.add_child(gh)


func _build_minimap() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -138
	box.offset_right = -6
	box.offset_top = 6
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	var mm := Minimap.new()
	mm.game = game
	box.add_child(mm)
	zone_label = Kit.label("", 9, Kit.GOLD)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(zone_label)


func _build_chat() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box("chat", 4))
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 6
	p.offset_right = 246
	p.offset_top = -104
	p.offset_bottom = -6
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_log.add_theme_font_size_override("normal_font_size", 9)
	chat_log.add_theme_constant_override("line_separation", -2)
	chat_log.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	chat_log.add_theme_constant_override("shadow_offset_x", 1)
	chat_log.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Enter — написать в чат"
	chat_input.max_length = 120
	chat_input.add_theme_font_size_override("font_size", 9)
	chat_input.custom_minimum_size = Vector2(0, 13)
	chat_input.text_submitted.connect(_on_chat_submit)
	chat_input.focus_exited.connect(func(): chat_input.release_focus())
	v.add_child(chat_input)


func _build_actions() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -84
	bar.offset_right = 50
	bar.offset_top = -38
	bar.offset_bottom = -6
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	bar.add_child(_action(Vector2i(0, 11), "C", "Герой: уровень, характеристики, умения", func(): ui.charwin.toggle()))
	bar.add_child(_action(Items.UI_ICONS.bag, "I", "Сумка", func(): ui.toggle_inventory()))
	bar.add_child(_action(Items.UI_ICONS.trade, "T", "Обмен с ближайшим игроком", func(): game.request_trade_nearest()))
	bar.add_child(_action(Vector2i(7, 10), "Esc", "Меню", func(): ui.toggle_menu()))


func _action(cell: Vector2i, key: String, tip: String, cb: Callable) -> Control:
	var s = ItemSlot.new()
	s.custom_minimum_size = Vector2(30, 30)
	s.tooltip_text = tip
	s.clicked.connect(func():
		Sfx.play("click")
		cb.call())
	var ic := Kit.icon(cell, 22)
	ic.position = Vector2(4, 3)
	ic.size = Vector2(22, 22)
	s.add_child(ic)
	var k := Kit.label(key, 9, Kit.GOLD)
	k.position = Vector2(2, 18)
	s.add_child(k)
	return s


func _build_banner() -> void:
	zone_banner = Kit.label("", 18, Kit.GOLD)
	zone_sub = Kit.label("", 9, Kit.DIM)
	for l in [zone_banner, zone_sub]:
		l.anchor_right = 1.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate.a = 0.0
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	zone_banner.offset_top = 40
	zone_sub.offset_top = 58


func _build_death() -> void:
	death = ColorRect.new()
	death.color = Color(0.25, 0.02, 0.04, 0.55)
	death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death.visible = false
	add_child(death)
	var l := Kit.label("ТЫ ПАЛ", 18, Kit.RED)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = -100
	l.offset_right = 100
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death.add_child(l)
	var s := Kit.label("возрождение в городе…", 9, Kit.TEXT)
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.offset_left = -100
	s.offset_right = 100
	s.offset_top = 18
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death.add_child(s)


# ---------- обновление ----------

func set_stamina(ratio: float) -> void:
	st_fill.size.x = 110.0 * clampf(ratio, 0.0, 1.0)
	st_fill.color = Color(0.85, 0.8, 0.3) if ratio > 0.3 else Color(0.9, 0.45, 0.25)


func set_res(me: Dictionary) -> void:
	var kind := Rules.res_kind(me)
	res_fill.color = Rules.RES_COLORS[kind]
	res_fill.size.x = 110.0 * clampf(float(me.get("res", 0)) / maxf(1.0, float(me.get("res_max", 100))), 0.0, 1.0)
	res_fill.get_parent().tooltip_text = "%s %d / %d" % [Rules.RES_NAMES[kind], int(me.get("res", 0)), int(me.get("res_max", 100))]
	skills.set_res(float(me.get("res", 0)))


func refresh(me: Dictionary) -> void:
	var ratio := clampf(float(me.hp) / float(me.max_hp), 0.0, 1.0)
	hp_fill.size.x = 106.0 * ratio
	hp_text.text = "%d / %d" % [me.hp, me.max_hp]
	var split := Items.split_coins(int(me.coins))
	for d in 4:
		var show: bool = int(split[d]) > 0 or d == 3
		coin_icons[d].visible = show
		coin_labels[d].visible = show
		coin_labels[d].text = str(split[d]) + " "
	face_tex.atlas = CharBaker.bake(me.equip, me.get("look", {}))
	death.visible = int(me.hp) <= 0
	var lvl := int(me.get("level", 1))
	lvl_label.text = str(lvl) + ("+" if int(me.get("points", 0)) > 0 else "")
	lvl_label.add_theme_color_override("font_color", Kit.GOLD if int(me.get("points", 0)) > 0 else Color.WHITE)
	xp_fill.size.x = 110.0 * clampf(float(me.get("xp", 0)) / Rules.xp_to_next(lvl), 0.0, 1.0)
	skills.sync(me)
	set_res(me)


func add_line(text: String, color: Color) -> void:
	chat_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "(")])


func add_chat(from: String, text: String) -> void:
	chat_log.append_text("[color=#f2c76b]%s:[/color] %s\n" % [from, text.replace("[", "(")])


func is_typing() -> bool:
	return chat_input.has_focus()


func open_chat() -> void:
	chat_input.grab_focus()


func _on_chat_submit(text: String) -> void:
	var t := text.strip_edges()
	chat_input.clear()
	chat_input.release_focus()
	if t != "":
		game.send_chat(t)


func _process(delta: float) -> void:
	zone_acc += delta
	if zone_acc < 0.4 or game == null:
		return
	zone_acc = 0.0
	var z := _zone_of(game.my_pos)
	zone_label.text = z[0]
	if z[0] != current_zone:
		current_zone = z[0]
		_show_banner(z[0], z[1])


func _zone_of(p: Vector2) -> Array:
	var zs: Dictionary = World.zones
	if World.in_town(p, 0.0):
		return ["Пепельный Брод", "безопасный город"]
	var s: Array = zs.slime
	if pow((p.x - s[0]) / (s[2] * 1.4), 2) + pow((p.y - s[1]) / (s[3] * 1.4), 2) < 1.0:
		return ["Слизневая топь", "слабые монстры · для новичков"]
	var g: Array = zs.golem
	if p.distance_to(Vector2(g[0], g[1])) < 200:
		return ["Круг Голема", "опасно · здесь пробуждается босс"]
	var w: Array = zs.wolf
	if p.x > w[0] - 40 and p.y > w[1] - 40 and p.x < w[2] + 40 and p.y < w[3] + 40:
		return ["Волчий лес", "волки · держись группой"]
	return ["Дикие земли", ""]


func _show_banner(title: String, sub: String) -> void:
	zone_banner.text = title
	zone_sub.text = sub
	for l: Label in [zone_banner, zone_sub]:
		var tw := l.create_tween()
		l.modulate.a = 0.0
		tw.tween_property(l, "modulate:a", 1.0, 0.4)
		tw.tween_interval(2.2)
		tw.tween_property(l, "modulate:a", 0.0, 0.8)
