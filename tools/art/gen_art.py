"""Generates the game's own pixel art into assets/custom/.

Run from anywhere:  python tools/art/gen_art.py [--preview PATH]
weapons.png: rows = sword, axe, dagger, abyss_blade; columns = rarity 0..5; 32x32 cells.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from pixel import blank, hstack  # noqa: E402
import weapons  # noqa: E402
import enemies  # noqa: E402
import gear  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "custom"
WEAPON_ROWS = ["sword", "axe", "dagger", "abyss_blade"]


def build_weapons():
    sheet = blank(32 * 6, 32 * len(WEAPON_ROWS))
    for r, name in enumerate(WEAPON_ROWS):
        for tier in range(6):
            if name == "sword":
                icon = weapons.sword(tier)
            elif name == "axe":
                icon = weapons.axe(tier)
            elif name == "dagger":
                icon = weapons.dagger(tier)
            else:
                icon = weapons.abyss_blade()
            sheet.alpha_composite(icon, (tier * 32, r * 32))
    return sheet


def preview(sheet, path, scale=5):
    from PIL import Image
    bg = Image.new("RGBA", (sheet.width * scale + 20, sheet.height * scale + 20), (34, 32, 44, 255))
    bg.alpha_composite(sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST), (10, 10))
    bg.save(path)


def build_enemies():
    sheets = {
        "slime.png": hstack([enemies.slime(f) for f in range(2)]),
        "wolf.png": hstack([enemies.wolf(f) for f in range(4)]),
        "golem.png": hstack([enemies.golem(f) for f in range(2)]),
    }
    for name, img in sheets.items():
        img.save(OUT / name)
    return sheets


GEAR_BASES = ["armor", "robe", "boots", "helm", "hood", "dawn_crown", "sword", "axe", "dagger", "abyss_blade"]


def build_char(preview_path=None):
    import json
    import character as ch
    cdir = OUT / "char"
    cdir.mkdir(parents=True, exist_ok=True)
    for old in cdir.glob("*.png"):
        old.unlink()
    L = {}
    manifest = {}
    for sex in ("m", "f"):                          # всё, что зависит от фигуры — отдельно для каждого пола
        ch.SEX = sex
        for layer in ("legs", "feet", "arms_back", "arms_front", "torso"):
            L[f"{sex}_body_{layer}"] = ch.sheet(lambda d, f, l=layer: ch.body_part(l, d, f))
        for race, rd in ch.RACES.items():
            for tone in rd["tones"]:
                L[f"{sex}_head_{race}_{tone}"] = ch.sheet(lambda d, f, r=race, t=tone: ch.head_part(d, f, r, t))
        for tone in ch.SKIN_TONES:
            for hl in ("hands", "hands_back"):
                L[f"{sex}_{hl}_{tone}"] = ch.sheet(lambda d, f, t=tone, h=hl: ch.hands_part(h, d, f, t))
        for base in GEAR_BASES:
            manifest.setdefault(base, [])
            for layer in ch.LAYERS:
                for r in range(6):
                    if base in ("dawn_crown", "abyss_blade") and r != 5:
                        continue
                    img = ch.sheet(lambda d, f, l=layer, rr=r: ch.gear_part(base, l, d, f, ch.RARITY_TRIM[rr]))
                    if img is None:
                        break
                    L[f"{sex}_{base}_{layer}_r{r}"] = img
                    if layer not in manifest[base]:
                        manifest[base].append(layer)
    ch.SEX = "m"
    for style in ch.HAIR_STYLES:                    # общее для обоих полов (голова одна и та же)
        for color in ch.HAIR_COLORS:
            L[f"hair_{style}_{color}"] = ch.sheet(lambda d, f, s=style, cc=color: ch.hair_part(d, f, s, cc))
    for color in ch.HAIR_COLORS:
        for bs in ch.BEARDS:
            L[f"beard_{bs}_{color}"] = ch.sheet(lambda d, f, b=bs, cc=color: ch.beard_part(d, f, b, cc))
        L[f"ears_{color}"] = ch.sheet(lambda d, f, cc=color: ch.cat_ears_part(d, f, cc))
        L[f"tail_{color}"] = ch.sheet(lambda d, f, cc=color: ch.tail_part(d, f, cc))
    for mk in ch.MARKS:
        L[f"marks_{mk}"] = ch.sheet(lambda d, f, k=mk: ch.marks_part(d, f, k))
    for name, img in L.items():
        if img is not None:
            img.save(cdir / f"{name}.png")
    meta = {"layers": ch.LAYERS, "gear": manifest, "skins": list(ch.SKIN_TONES), "races": ch.RACES,
            "frames": len(ch.FRAMES), "cell": ch.CELL, "hair_styles": ch.HAIR_STYLES,
            "hair_colors": list(ch.HAIR_COLORS), "beards": ch.BEARDS, "marks": ch.MARKS, "eye_key": ch.EYE_KEY}
    (cdir / "char.json").write_text(json.dumps(meta), encoding="utf-8")
    if preview_path:
        looks = [("m", "human", "light", "short", "brown", "stubble", None, {"sword": 0}),
                 ("f", "human", "mid", "braid", "red", None, "freckles", {"dagger": 2}),
                 ("f", "elf", "pale", "long", "blond", None, None, {"robe": 3}),
                 ("m", "dwarf", "mid", "bun", "red", "full", "scar", {"axe": 2}),
                 ("m", "orc", "green", "spiky", "black", None, "warpaint", {"armor": 2, "axe": 4}),
                 ("f", "undead", "ash", "bob", "white", None, None, {"abyss_blade": 5}),
                 ("f", "felin", "light", "short", "blond", None, None, {"sword": 1}),
                 ("m", "goblin", "lime", "spiky", "black", "moustache", None, {"dagger": 1})]
        slot_of = {"armor": "body", "robe": "body", "boots": "feet", "helm": "head", "hood": "head",
                   "dawn_crown": "head", "sword": "weapon", "axe": "weapon", "dagger": "weapon", "abyss_blade": "weapon"}
        rows = []
        for sex, race, tone, style, color, beard, mark, equip in looks:
            by_slot = {slot_of[b]: (b, r) for b, r in equip.items()}
            sheet = blank(ch.CELL * len(ch.FRAMES), ch.CELL * 3)
            dy = ch.RACES[race].get("dy", 0)
            for layer in ch.LAYERS:
                slot = {"torso": "body", "arms_front": "body", "arms_back": "body", "skirt": "body", "feet": "feet",
                        "headgear": "head", "hat": "head", "weapon": "weapon", "weapon_back": "weapon"}.get(layer)
                name = None
                if slot in by_slot and layer in manifest[by_slot[slot][0]]:
                    b, r = by_slot[slot]
                    name = f"{sex}_{b}_{layer}_r{r}"
                elif layer == "head":
                    name = f"{sex}_head_{race}_{tone}"
                elif layer in ("hands", "hands_back"):
                    name = f"{sex}_{layer}_{tone}"
                elif layer == "headgear":
                    name = f"hair_{style}_{color}"
                elif layer == "beard":
                    b = "full" if race == "dwarf" and sex == "m" else beard
                    name = f"beard_{b}_{color}" if b else None
                elif layer == "marks":
                    name = f"marks_{mark}" if mark else None
                elif layer == "ears":
                    name = f"ears_{color}" if race == "felin" else None
                elif layer == "tail":
                    name = f"tail_{color}" if race == "felin" else None
                elif layer in ("legs", "feet", "arms_back", "arms_front", "torso"):
                    name = f"{sex}_body_{layer}"
                if name and L.get(name) is not None:
                    sheet.alpha_composite(L[name], (0, 0 if layer in ("legs", "feet") else dy))
            rows.append(sheet)
        out = blank(ch.CELL * len(ch.FRAMES), ch.CELL * 3 * len(rows))
        for i, s in enumerate(rows):
            out.alpha_composite(s, (0, i * ch.CELL * 3))
        preview(out, preview_path, scale=2)
    print("char layers ok", len(L))

def gear_on_body(g):
    """Preview: each gear row drawn over the base character idle frames (down, up, side)."""
    from PIL import Image
    body = Image.open(ROOT / "assets" / "darkworld" / "character_sheet.png").convert("RGBA")
    frames = [body.crop((0, r * 32, 32, r * 32 + 32)) for r in range(3)]
    out = blank(32 * 3 * 2 + 8, g.height)
    for r in range(g.height // 32):
        for d in range(3):
            cell = g.crop((d * 32, r * 32, d * 32 + 32, r * 32 + 32))
            out.alpha_composite(frames[d], (d * 32, r * 32))
            out.alpha_composite(cell, (d * 32, r * 32))
            out.alpha_composite(frames[d], (96 + 8 + d * 32, r * 32))
    return out


def build_world(preview_path=None):
    from PIL import Image
    import props
    import world
    pdir = OUT / "props"
    pdir.mkdir(parents=True, exist_ok=True)
    sprites = dict(props.PROPS)
    sprites["deadtree"] = Image.open(ROOT / "assets" / "darkworld" / "tree.png").convert("RGBA")
    import json
    import props25d
    meta = {}
    for name, img in sprites.items():
        img.save(pdir / f"{name}.png")
        if name not in getattr(props, "NO_SHADOW", set()) and not name.startswith("campfire"):
            props25d.shadow_of(img).save(pdir / f"{name}_shadow.png")
            meta[name] = True
    (pdir / "shadows.json").write_text(json.dumps(meta), encoding="utf-8")
    ground, lay = world.build(OUT / "world")
    full = ground.convert("RGBA")
    for p in lay["props"]:
        if p["k"] in meta:
            sh = props25d.shadow_of(sprites[p["k"]])
            full.alpha_composite(sh, (p["x"] - sprites[p["k"]].width // 2, p["y"] - sh.height))
    for p in lay["props"]:
        s = sprites[p["k"]]
        full.alpha_composite(s, (p["x"] - s.width // 2, p["y"] - s.height))
    full.crop((1000, 720, 1640, 1080)).save(OUT / "world" / "menu_bg.png")   # town gate, road, bridge
    if preview_path:
        full.resize((W_ // 2, H_ // 2), Image.NEAREST).save(preview_path.replace(".png", "_map.png"))
        town = full.crop((700, 740, 1340, 1240))
        town.resize((town.width * 2, town.height * 2), Image.NEAREST).save(preview_path.replace(".png", "_town.png"))
    print("world props", len(lay["props"]), "rects", len(lay["rects"]), "circles", len(lay["circles"]))


W_, H_ = 2400, 1600


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if "--char" in sys.argv:
        build_char(sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None)
        return
    if "--ui" in sys.argv:
        import ui_kit
        udir = OUT / "ui"
        udir.mkdir(parents=True, exist_ok=True)
        for name, img in ui_kit.KIT.items():
            img.save(udir / f"{name}.png")
        if "--preview" in sys.argv:
            strip = hstack([i for i in ui_kit.KIT.values()])
            preview(strip, sys.argv[sys.argv.index("--preview") + 1], scale=6)
        print("ui", list(ui_kit.KIT))
        return
    if "--world" in sys.argv:
        build_world(sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None)
        return
    w = build_weapons()
    w.save(OUT / "weapons.png")
    e = build_enemies()
    g = gear.sheet()
    g.save(OUT / "gear.png")
    if "--preview" in sys.argv:
        path = sys.argv[sys.argv.index("--preview") + 1]
        preview(w, path)
        preview(gear_on_body(g), path.replace(".png", "_gear.png"), scale=5)
        strip = blank(sum(i.width for i in e.values()) + 40, max(i.height for i in e.values()))
        x = 0
        for img in e.values():
            strip.alpha_composite(img, (x, strip.height - img.height))
            x += img.width + 20
        preview(strip, path.replace(".png", "_enemies.png"), scale=6)
    print("ok", w.size, {k: v.size for k, v in e.items()})


if __name__ == "__main__":
    main()
