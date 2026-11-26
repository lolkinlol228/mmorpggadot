extends RefCounted
## Собирает спрайт-лист героя из слоёв (tools/art/character.py): раса + тело + надетые вещи.
## Все слои нарисованы по одному скелету, поэтому броня «сидит» на теле в каждом кадре.
## Раса меняет голову (уши, клыки, глаза), добавляет бороду / кошачьи уши / хвост и рост:
## верх тела сдвигается вниз (дварф — ниже) или вверх (эльф — выше).
## Столбцы: 0-1 стойка, 2-5 ходьба, 6-9 бег, 10-12 рубящий удар, 13-15 удар сверху,
## 16-18 укол, 19 взаимодействие, 20 урон. Строки: вниз, вверх, бок (смотрит вправо).

const DIR := "res://assets/custom/char/"
const SLOT_FOR_LAYER := {"torso": "body", "arms_front": "body", "arms_back": "body", "skirt": "body",
	"feet": "feet", "headgear": "head", "hat": "head", "weapon": "weapon", "weapon_back": "weapon"}
const DEFAULT_LOOK := {"race": "human", "sex": "m", "skin": "light", "hair": "short", "hair_color": "brown",
	"eyes": "brown", "beard": "none", "marks": "none"}
const EYES := {"brown": Color8(110, 70, 42), "blue": Color8(70, 124, 214), "green": Color8(72, 156, 84),
	"grey": Color8(132, 142, 156), "amber": Color8(214, 150, 40)}
const SEX_SHARED := ["hair_", "beard_", "ears_", "tail_", "marks_"]   # эти листы общие для обоих полов
const LOWER := ["legs", "feet"]                 # всё остальное — «верх», его сдвигает рост расы
const CELL := 48
const FRAMES := 21
const SHEET_SIZE := Vector2i(CELL * FRAMES, CELL * 3)
const RACE_NAMES := {"human": "человек", "elf": "эльф", "dwarf": "дварф", "orc": "орк",
	"undead": "нежить", "felin": "кошколюд", "goblin": "гоблин"}

static var meta := {}
static var _imgs := {}
static var _cache := {}


static func _load_meta() -> void:
	if meta.is_empty():
		meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "char.json"))


static func _img(name: String) -> Image:
	if not _imgs.has(name):
		var path := DIR + name + ".png"
		var img: Image = null
		if ResourceLoader.exists(path):
			img = (load(path) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
		_imgs[name] = img
	return _imgs[name]


static func _layer_source(layer: String, equip: Dictionary, look: Dictionary) -> String:
	var slot: String = SLOT_FOR_LAYER.get(layer, "")
	var it = equip.get(slot) if slot != "" else null
	var art: String = str(Items.BASES.get(it.base, {}).get("art", it.base)) if it is Dictionary else ""
	if it is Dictionary and meta.gear.has(art) and layer in meta.gear[art]:
		var r := 5 if art in ["dawn_crown", "abyss_blade"] else int(it.rarity)
		return "%s_%s_%s_r%d" % [look.sex, art, layer, r]
	var head = equip.get("head")
	var covered: bool = head is Dictionary and head.base in ["helm", "hood"]
	match layer:
		"head":
			return "%s_head_%s_%s" % [look.sex, look.race, look.skin]
		"hands", "hands_back":
			return "%s_%s_%s" % [look.sex, layer, look.skin]
		"marks":
			return "marks_" + look.marks if look.marks != "none" else ""
		"headgear":
			return "hair_%s_%s" % [look.hair, look.hair_color]
		"hair_back":                                  # пряди за плечами; под шлемом их нет
			var full: bool = head is Dictionary and head.base == "helm"
			return "" if full else "hairb_%s_%s" % [look.hair, look.hair_color]
		"beard":
			return "beard_%s_%s" % [look.beard, look.hair_color] if look.beard != "none" else ""
		"ears":
			return "ears_" + look.hair_color if look.race == "felin" and not covered else ""
		"tail":
			return "tail_" + look.hair_color if look.race == "felin" else ""
		"skirt", "hat", "weapon", "weapon_back":
			return ""
	return "%s_body_%s" % [look.sex, layer]


static func sanitize_look(look) -> Dictionary:
	_load_meta()
	var out := DEFAULT_LOOK.duplicate()
	if look is Dictionary:
		if str(look.get("race", "")) in meta.races: out.race = str(look.race)
		var tones: Array = meta.races[out.race].tones
		out.skin = str(look.get("skin", "")) if str(look.get("skin", "")) in tones else tones[0]
		if str(look.get("hair", "")) in meta.hair_styles: out.hair = str(look.hair)
		if str(look.get("hair_color", "")) in meta.hair_colors: out.hair_color = str(look.hair_color)
		if str(look.get("sex", "")) in ["m", "f"]: out.sex = str(look.sex)
		if str(look.get("eyes", "")) in EYES: out.eyes = str(look.eyes)
		if str(look.get("beard", "")) in meta.beards: out.beard = str(look.beard)
		if str(look.get("marks", "")) in meta.marks: out.marks = str(look.marks)
	if out.sex == "f":
		out.beard = "none"
	elif out.race == "dwarf" and out.beard == "none":
		out.beard = "full"                                    # дварф без бороды — не дварф
	return out


static func bake(equip: Dictionary, look: Dictionary = {}) -> Texture2D:
	_load_meta()
	look = sanitize_look(look)
	var dy := int(meta.races[look.race].get("dy", 0))
	var w := int(meta.races[look.race].get("w", 0))
	var parts: Array = []
	for layer in meta.layers:
		parts.append([layer, _layer_source(layer, equip, look)])
	var sig := "%s|%d|%d|%s" % [str(parts), dy, w, look.eyes]      # цвет глаз тоже меняет картинку
	if _cache.has(sig):
		return _cache[sig]
	var out := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	var rect := Rect2i(Vector2i.ZERO, SHEET_SIZE)
	for p in parts:
		if p[1] == "":
			continue
		var src := _img(p[1])
		if src == null:
			continue
		if p[0] in LOWER:
			out.blend_rect(src, rect, Vector2i.ZERO)
			if dy < 0 and p[0] == "legs":                 # эльф: ноги длиннее — без щели под туникой
				out.blend_rect(src, rect, Vector2i(0, dy))
		else:
			out.blend_rect(src, rect, Vector2i(0, dy))
	_recolor_eyes(out, EYES[look.eyes])
	if w != 0:
		out = _reshape(out, w)
	var tex := ImageTexture.create_from_image(out)
	_cache[sig] = tex
	return tex


## Телосложение расы: w > 0 раздвигает левую и правую половины кадра от оси (орк, дварф — шире,
## повторяя центральные столбцы), w < 0 вынимает столбец у оси (эльф, гоблин, нежить — уже).
## Делается по готовому кадру, поэтому голова, волосы и броня меняются вместе с телом.
static func _reshape(src: Image, w: int) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	var mid := CELL >> 1                                 # ось тела: между столбцами 23 и 24
	for row in 3:
		for col in FRAMES:
			var o := Vector2i(col * CELL, row * CELL)
			if w > 0:
				var a := w / 2
				out.blit_rect(src, Rect2i(o + Vector2i(a, 0), Vector2i(mid - a, CELL)), o)
				out.blit_rect(src, Rect2i(o + Vector2i(mid, 0), Vector2i(mid - a, CELL)), o + Vector2i(mid + a, 0))
				for i in a:
					out.blit_rect(src, Rect2i(o + Vector2i(mid - 1, 0), Vector2i(1, CELL)), o + Vector2i(mid - 1 - i, 0))
					out.blit_rect(src, Rect2i(o + Vector2i(mid, 0), Vector2i(1, CELL)), o + Vector2i(mid + i, 0))
			else:
				var k := -w
				out.blit_rect(src, Rect2i(o, Vector2i(mid, CELL)), o)
				out.blit_rect(src, Rect2i(o + Vector2i(mid + k, 0), Vector2i(mid - k, CELL)), o + Vector2i(mid, 0))
	return out


## Радужка нарисована цветом-ключом — меняем на выбранный цвет глаз.
static func _recolor_eyes(img: Image, eye: Color) -> void:
	var k: Array = meta.eye_key
	var key := Color8(int(k[0]), int(k[1]), int(k[2]))
	for row in 3:                                   # глаза только в верхней части клетки
		for y in range(row * CELL + 8, row * CELL + 26):
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and absf(p.r - key.r) < 0.02 and absf(p.g - key.g) < 0.02 and absf(p.b - key.b) < 0.02:
					img.set_pixel(x, y, eye)