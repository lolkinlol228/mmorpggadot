extends Sprite2D
## Покадровый эффект из assets/custom/vfx/<name>.png (кадры в ряд, tools/art/vfx.py).
## Проигрывается один раз и удаляет себя. Vfx.play(parent, "fire_burst", pos, {scale, rot, color, fps, add, z, anchor})
##   anchor "bottom" — низ спрайта в точке (столп света, лечение), иначе — центр.

const FRAMES := {"fire_burst": 8, "frost_nova": 8, "holy_pillar": 8, "meteor": 4, "slash": 5,
	"hit_spark": 5, "heal": 8, "shockwave": 6, "ring": 6}
const DIR := "res://assets/custom/vfx/"     # load() сам кэширует текстуры, свой кэш не нужен

var fps := 16.0
var t := 0.0
var loop_for := 0.0          # > 0 — крутить кадры по кругу столько секунд (летящий метеор)


static func play(parent: Node, name: String, pos: Vector2, opts: Dictionary = {}) -> Node2D:
	var v = preload("res://scripts/vfx.gd").new()
	v.texture = load(DIR + name + ".png")
	v.hframes = FRAMES[name]
	v.position = pos
	v.scale = Vector2.ONE * float(opts.get("scale", 1.0))
	v.rotation = float(opts.get("rot", 0.0))
	v.modulate = opts.get("color", Color.WHITE)
	v.fps = float(opts.get("fps", 16.0))
	v.loop_for = float(opts.get("loop", 0.0))
	v.z_index = int(opts.get("z", 42))
	v.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if opts.get("anchor", "") == "bottom":
		v.centered = false
		v.offset = Vector2(-v.texture.get_width() / float(v.hframes) / 2.0, -v.texture.get_height())
	if opts.get("add", false):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		v.material = m
	parent.add_child(v)
	return v


func _process(delta: float) -> void:
	t += delta
	var f := int(t * fps)
	if loop_for > 0.0:
		frame = f % hframes
		if t >= loop_for:
			queue_free()
		return
	if f >= hframes:
		queue_free()
		return
	frame = f
