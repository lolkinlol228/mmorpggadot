extends Node
## Расставляет объекты карты (дома, деревья, стены…) внутрь узла с y-сортировкой,
## чтобы герой заходил «за» дом или дерево. Фонари и костёр светятся.

const DIR := "res://assets/custom/props/"
const PAD := 3                       # прозрачный запас по краям спрайта (tools/art/shade.py)
const NO_PAD := ["wall_h", "wall_v"]
const SWAY := ["pine", "pine_big", "pine_small", "bush", "bush_berry"]
var _sway_mat: ShaderMaterial
const LIGHTS := {"lamp": [Vector2(0, -29), 28.0], "campfire0": [Vector2(0, -10), 42.0]}

var _tex := {}
var _shadows := {}


func populate(sorted_parent: Node2D, shadow_parent: Node2D) -> void:
	var sj = JSON.parse_string(FileAccess.get_file_as_string(DIR + "shadows.json"))
	if sj is Dictionary:
		_shadows = sj
	for p in World.props:
		var kind: String = p.k
		var tex: Texture2D = _texture(kind)
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var pad := 0 if kind in NO_PAD else PAD
		s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() + pad)
		s.position = Vector2(p.x, p.y)
		if kind in SWAY:
			if _sway_mat == null:
				_sway_mat = ShaderMaterial.new()
				_sway_mat.shader = load("res://shaders/sway.gdshader")
			s.material = _sway_mat
		sorted_parent.add_child(s)
		if _shadows.has(kind):
			var sh := Sprite2D.new()
			var st: Texture2D = _texture(kind + "_shadow")
			sh.texture = st
			sh.centered = false
			sh.offset = Vector2(-tex.get_width() / 2.0, -st.get_height() + pad)
			sh.position = s.position
			shadow_parent.add_child(sh)
		if kind in ["house", "forge", "tavern"]:
			s.add_child(_smoke(s.offset + Vector2(tex.get_width() - 19, 3)))   # труба: 19 px от правого края текстуры
		if kind == "campfire0":
			_animate_fire(s)
		if LIGHTS.has(kind):
			s.add_child(_glow(LIGHTS[kind][0], LIGHTS[kind][1], kind == "campfire0"))


func _smoke(at: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = 12
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.direction = Vector2(0.35, -1)
	p.spread = 14
	p.gravity = Vector2(5, -3)
	p.initial_velocity_min = 7
	p.initial_velocity_max = 11
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(0.7, 0.68, 0.72, 0.0), Color(0.74, 0.72, 0.76, 0.8), Color(0.6, 0.58, 0.62, 0.0)])
	p.color_ramp = fade
	return p


func _texture(kind: String) -> Texture2D:
	if not _tex.has(kind):
		var path := DIR + kind + ".png"
		_tex[kind] = load(path) if ResourceLoader.exists(path) else null
	return _tex[kind]


func _animate_fire(s: Sprite2D) -> void:
	var frames := [_texture("campfire0"), _texture("campfire1")]
	var timer := Timer.new()
	timer.wait_time = 0.18
	timer.autostart = true
	var i := [0]
	timer.timeout.connect(func():
		i[0] = (i[0] + 1) % 2
		s.texture = frames[i[0]])
	s.add_child(timer)


## Мягкое тёплое свечение (аддитивное), слегка «дышит».
func _glow(offset: Vector2, radius: float, flicker: bool) -> Node2D:
	var g := Node2D.new()
	g.position = offset
	g.z_index = 5
	g.z_as_relative = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.set_script(load("res://scripts/glow.gd"))
	g.set("radius", radius)
	g.set("flicker", flicker)
	return g
