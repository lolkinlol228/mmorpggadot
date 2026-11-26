extends SceneTree
## Проверка контракта каталога и формул даров.

const Gifts := preload("res://scripts/gifts.gd")

const MODS := "all aoe armor aspd bag bank block buff_dur buff_power buy_price carry cc_resist cd chest_coin coin cook craft_rare craft_speed craft_xp crit crit_dmg dash_cd dash_charges dash_dist dmg dmg_taken_melee dmg_taken_ranged dodge dot food gather_cloth gather_fish gather_hide gather_ore gather_wood heal heal_taken hp hp_regen lifesteal loot mana mana_cost mana_regen mega_rare mythic_find parry_cost parry_window pickup rare_find revive_speed salvage sell_price skill_crit skill_dmg speed sprint_cost sprint_speed stam_regen thorns tool_wear xp xp_carpenter xp_mining xp_smith xp_tailor xp_tanner"
const CONDITIONS := "blade blunt day dungeon far_target group in_forest low_hp near_ally night not_hurt3 on_road one_enemy outnumbered still target_low vs_big vs_elite vs_golem vs_slime vs_undead vs_wolf"
const PROCS := "bleed bleed_stack buff_aspd buff_dmg buff_speed burn burn_near cd_all cd_reset chain coin_mult dash_dmg decoy delayed_heal double free_craft gem gold_drop golden_item heal heal_allies instakill invuln knockback mana next_hit_mult no_deplete parry_reset poison quake rare_mat reflect repeat repeat_skill self_dmg shield_from_dmg slow stack_dmg stun summon_wolf sunder weaken whirl"
const EVENTS := "combat_end combat_start craft dash death dodge gather gather_cloth gather_hide gather_ore gather_wood hit hurt kill loot low_hp parry skill tick"
const FLAGS := "adapt all_elite ally_cheat_death any_weapon aura_banner aura_dmg8 aura_stam aura_xp beast_passive berserk blink_dash block30 boss_aggro_loot cd90 cheat_death300 cleave cold_resist combo4 copy_gift counter_parry coward craft_extra_affix craft_mythic craft_rarity_up crit_chain cross_skill dash_reset_hit death_penalty3 demon_tax devourer diamond3 dmg_cap25 dungeon_revive echo5 empath enemies_stronger25 execute15 fate_blade fear_weak fire_immune first_crit fists food_share free_sprint gold_power heal_aura heal_splash herbs hourly_gift hp_cost hydra kill_streak king lone_wolf lunatic mana_scaling mana_shield10 meteor momentum night_owl night_vision no_armor no_fail no_heal no_terrain_slow no_water_slow orbit overheal_shield pack pet_companion poison_immune rally random_dmg rarity_gamble recall300 respawn_shield revive_heal run_charge scroll_boost see_caches see_ore see_traps self_revive600 share_dmg30 share_gifts share_loot shop_extra staff tame threat_up time_stop titan_grip tool_tier_up transmute tree_strike unstoppable vampire"

var failures := 0


## Запускает проверки после инициализации автозагрузок.
func _initialize() -> void:
	call_deferred("_run")


## Проверяет условие без прерывания остальных проверок.
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr(message)


## Проверяет, что таблица покрытия учитывает каждую часть дара.
func check_catalog() -> void:
	var ids := {}
	var catalog := Gifts.all()
	check(catalog.size() == 250, "Ожидалось 250 даров, получено %d" % catalog.size())
	for g: Dictionary in catalog:
		var id := str(g.id)
		check(not ids.has(id), "Повторяющийся id: " + id)
		ids[id] = true
		for key in g.get("mods", {}):
			check(key in MODS.split(" "), "%s: неизвестный модификатор %s" % [id, key])
		if g.has("when"):
			check(g.when in CONDITIONS.split(" "), "%s: неизвестное условие %s" % [id, g.when])
		if g.has("flag"):
			check(g.flag in FLAGS.split(" "), "%s: неизвестный флаг %s" % [id, g.flag])
		if g.has("proc"):
			var proc: Array = g.proc
			check(proc.size() == 4, "%s: неверный формат эффекта" % id)
			if proc.size() != 4:
				continue
			check(proc[0] in EVENTS.split(" "), "%s: неизвестное событие %s" % [id, proc[0]])
			check(float(proc[1]) >= 0.0 and float(proc[1]) <= 1.0, "%s: шанс вне 0..1" % id)
			check(proc[2] in PROCS.split(" "), "%s: неизвестный эффект %s" % [id, proc[2]])


## Проверяет базовые формулы, потолки и старые сохранения.
func check_rules() -> void:
	var rules: Node = root.get_node("Rules")
	var save: Node = root.get_node("Save")
	var p := {"cls": "mage", "level": 1, "stats": {}, "gifts": []}
	var base_damage: float = rules.damage(p)
	var base_hp: int = rules.max_hp(p)
	var base_cost: int = rules.skill_cost(p, "fireball")
	var base_speed: float = rules.speed_mult(p)
	p.gifts = ["strong_arm"]
	check(is_equal_approx(rules.damage(p), base_damage * 1.08), "strong_arm: +8% урона")
	p.gifts = ["glass_cannon"]
	check(is_equal_approx(rules.damage(p), base_damage * 1.35), "glass_cannon: +35% урона")
	check(rules.max_hp(p) < base_hp, "glass_cannon: здоровье ниже")
	p.gifts = ["fortress"]
	check(rules.max_hp(p) > base_hp, "fortress: здоровье выше")
	p.gifts = ["archmage"]
	check(rules.skill_cost(p, "fireball") < base_cost, "archmage: стоимость ниже")
	p.gifts = ["swift"]
	check(is_equal_approx(rules.speed_mult(p), base_speed * 1.08), "swift: +8% скорости")
	p.gifts = ["precision", "sharp_eye", "four_leaf", "lucky"]
	p.stats.agi = 300
	check(is_equal_approx(rules.crit_chance(p), Gifts.CAPS.crit), "Шанс крита ограничен 60%")
	p.gifts = ["archmage"]
	p.stats.spi = 300
	check(is_equal_approx(rules.cd_mult(p), Gifts.CAPS.cd_mult_min), "Множитель перезарядки ограничен снизу")
	check(save.sanitize_char({}).gift_state.fate_blade == 0, "Старое сохранение без gift_state")
	check(save.sanitize_char({"gift_state": {"fate_blade": 42}}).gift_state.fate_blade == 42, "Клинок судьбы сохраняет счётчик")


## Проверяет условные добавки, порог здоровья и защиту босса.
func check_host() -> void:
	var host_script := load("res://scripts/host_logic.gd") as GDScript
	var gifts_script := load("res://scripts/host_gifts.gd") as GDScript
	if host_script == null or gifts_script == null or not host_script.can_instantiate() or not gifts_script.can_instantiate():
		check(false, "Скрипты хоста не компилируются")
		return
	var host: Node = host_script.new()
	var gifts: Node = gifts_script.new()
	gifts.host = host
	var p := {"hp": 30, "max_hp": 100, "pos": Vector2.ZERO, "gifts": ["unbending", "duelist", "keen_edge"], "equip": {"weapon": {"base": "sword"}}}
	var boss := {"hp": 1000, "max_hp": 1000, "kind": "golem", "pos": Vector2(80, 0)}
	host.players[1] = p
	host.enemies[2] = boss
	check(is_equal_approx(gifts.mod(1, "dmg", {"enemy": boss}), 0.18), "Условия боя складываются на хосте")
	check(is_equal_approx(gifts.mod(1, "armor"), 0.25), "Броня применяется ниже порога здоровья")
	p.hp = 35
	check(is_zero_approx(gifts.mod(1, "armor")), "При 35% условие low_hp выключено")
	var ctx := {"eid": 2, "enemy": boss}
	gifts.effect(1, "instakill", 1.0, ctx)
	check(boss.hp == 1000, "Мгновенное убийство не действует на голема")
	gifts.effect(1, "slow", 4.0, ctx)
	check(int(boss.slow_until) - gifts.now() <= 1000 and int(boss.slow_until) > gifts.now(), "Замедление голема в четыре раза короче")
	for i in 12:
		gifts.add_dot(1, boss, "bleed_stack", 1.0, ctx)
	check(boss.gift_dots.size() == Gifts.DOT_MAX_STACKS, "Ограничение числа стаков DoT")
	p.gifts = ["thousand_cuts", "counter"]
	boss.gift_dots.clear()
	gifts.fire(1, "hit", ctx)
	gifts.fire(1, "hit", ctx)
	check(boss.gift_dots.size() == 1, "Повторное событие hit ограничено интервалом дара")
	gifts.fire(1, "parry", ctx)
	check(is_equal_approx(p.gift_next_hit, 1.8), "Ответный удар срабатывает при парировании")
	gifts.free()
	host.free()


## Печатает результат и завершает тест с кодом ошибки при нарушении.
func _run() -> void:
	check_catalog()
	check_rules()
	check_host()
	if failures == 0:
		print("OK: 250 даров, пассивные формулы, сохранения, условия хоста и ограничения баланса.")
	else:
		printerr("Ошибок: %d" % failures)
	quit(0 if failures == 0 else 1)
