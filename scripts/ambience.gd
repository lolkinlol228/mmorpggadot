extends Node
## «Жизнь» мира: смена дня и ночи, виньетка, блеск реки, дым из труб, светлячки над топью,
## листопад в лесу, бабочки на лугу, жители города. Время суток общее для всех игроков
## (считается от системных часов), поэтому синхронизировать его по сети не нужно.

const PlayerView := preload("res://scripts/player_view.gd")
const WATER_MASK := preload("res://assets/custom/world/water_mask.png")
const DAY_LENGTH := 480.0          # секунд на полный цикл
const CHIMNEY := {"house": 24.0, "forge": 26.0, "tavern": 28.0}

var game
var tint: CanvasModulate
var vignette: ColorRect
var fireflies: CPUParticles2D
var palette := [
	[0.00, Color(1.0, 1.0, 1.0)],          # день
	[0.45, Color(1.0, 1.0, 1.0)],
	[0.55, Color(1.0, 0.86, 0.76)],        # закат
	[0.65, Color(0.52, 0.56, 0.82)],       # ночь
	[0.90, Color(0.52, 0.56, 0.82)],
	[1.00, Color(1.0, 1.0, 1.0)],          # рассвет
]


func build(entities: Node2D) -> void:
	tint = CanvasModulate.new()
	game.add_child(tint)
	var water := Sprite2D.new()
	water.texture = WATER_MASK
	water.centered = false
	water.z_index = -9
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	water.material = wm
	game.add_child(water)
	var layer := CanvasLayer.new()
	layer.layer = 1
	game.add_child(layer)
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vm
	layer.add_child(vignette)
	_fireflies()
	_leaves()
	_butterflies()
	_npcs(entities)


# ---------- день и ночь ----------

func _process(_delta: float) -> void:
	var phase := fmod(Time.get_unix_time_from_system(), DAY_LENGTH) / DAY_LENGTH
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--night"):
		phase = 0.75
	elif OS.is_debug_build() and OS.get_cmdline_user_args().has("--day"):
		phase = 0.2
	var c: Color = palette[0][1]
	for i in range(palette.size() - 1):
		var a: Array = palette[i]
		var b: Array = palette[i + 1]
		if phase >= a[0] and phase <= b[0]:
			c = (a[1] as Color).lerp(b[1], (phase - a[0]) / maxf(0.001, b[0] - a[0]))
			break
	tint.color = c
	World.night = clampf((1.0 - c.g) / 0.44, 0.0, 1.0)
	(vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.35 + World.night * (0.08 if Rules.Gifts.has_flag(game.me, "night_vision") else 0.35))
	fireflies.modulate.a = 0.25 + World.night * 0.75


# ---------- частицы ----------

func _particles(pos: Vector2, rect: Vector2, amount: int, life: float, color: Color, additive := false) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = rect
	p.color = color
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	return p


func _fireflies() -> void:
	var s: Array = World.zones.slime
	fireflies = _particles(Vector2(s[0], s[1]), Vector2(s[2] * 1.2, s[3] * 1.2), 70, 5.0, Color(0.85, 1.0, 0.45), true)
	fireflies.gravity = Vector2.ZERO
	fireflies.direction = Vector2(1, 0)
	fireflies.spread = 180
	fireflies.initial_velocity_min = 2
	fireflies.initial_velocity_max = 7
	fireflies.scale_amount_max = 2.0
	fireflies.z_index = 30
	var blink := Gradient.new()
	blink.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
	blink.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	fireflies.color_ramp = blink
	game.add_child(fireflies)


func _leaves() -> void:
	var w: Array = World.zones.wolf
	var centre := Vector2((w[0] + w[2]) / 2.0, (w[1] + w[3]) / 2.0)
	var ext := Vector2((w[2] - w[0]) / 2.0 + 40, (w[3] - w[1]) / 2.0 + 40)
	for col in [Color(0.35, 0.5, 0.3), Color(0.55, 0.42, 0.25)]:
		var p := _particles(centre, ext, 90, 7.0, col)
		p.gravity = Vector2(4, 9)
		p.direction = Vector2(1, 0.3)
		p.initial_velocity_min = 3
		p.initial_velocity_max = 9
		p.angular_velocity_min = -90
		p.angular_velocity_max = 90
		p.scale_amount_max = 2.0
		p.z_index = 30
		game.add_child(p)


func _butterflies() -> void:
	for spot in [Vector2(480, 1060), Vector2(1020, 1240), Vector2(700, 760)]:
		for col in [Color(1, 1, 1), Color(1, 0.85, 0.35)]:
			var p := _particles(spot, Vector2(150, 90), 6, 6.0, col)
			p.gravity = Vector2.ZERO
			p.direction = Vector2(1, 0)
			p.spread = 180
			p.initial_velocity_min = 8
			p.initial_velocity_max = 16
			p.damping_min = 2
			p.damping_max = 6
			p.scale_amount_max = 2.0
			p.z_index = 30
			game.add_child(p)


# ---------- жители ----------

func _npcs(entities: Node2D) -> void:
	for n in World.zones.get("npcs", []):
		var v := PlayerView.new()
		v.pid = -1
		v.pname = "%s · %s" % [n[0], n[1]]
		v.look = n[4]
		var eq := {}
		for slot in n[5]:
			eq[slot] = Items.make(n[5][slot][0], int(n[5][slot][1]), "", false)
		v.equip = eq
		v.position = Vector2(n[2], n[3])
		v.target = v.position
		v.move_dir = {"down": Vector2.DOWN, "up": Vector2.UP, "side_left": Vector2.LEFT, "side_right": Vector2.RIGHT}.get(n[6], Vector2.DOWN)
		v.npc = true
		entities.add_child(v)
		World.add_circle(v.position, 6.0)
