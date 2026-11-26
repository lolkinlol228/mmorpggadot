# Задание для Codex: движок «Даров судьбы»

Скопируй всё ниже в Codex целиком.

---

Ты работаешь в проекте `C:\Users\isi08\Desktop\coop-rpg`. Это кооперативная 2D пиксельная RPG на **Godot 4.7.2** (GDScript, рендер gl_compatibility). Путь к Godot:
`C:\Users\isi08\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`

## Задача

Сделать так, чтобы **дары судьбы работали в игре**. Дары — врождённые особенности героя, их выдаёт бросок при создании героя (1 дар, иногда 2–3). Каталог из 250 даров уже лежит в `data/gifts.json`. Загрузка, бросок и показ даров в интерфейсе уже сделаны. **Эффекты даров не работают** — это и есть твоя задача.

## Как устроен проект (прочитай перед работой)

**Сеть: хост решает всё.** Один игрок — хост (ENet-сервер), остальные подключаются по IP.
- Клиент шлёт хосту RPC с префиксом `h_` из `scripts/game.gd` (например, `h_attack`, `h_skill`).
- Хост отвечает RPC с префиксом `c_` (например, `c_enemy_hit`, `c_hp`, `c_self`).
- Помощники в `scripts/host_logic.gd`:
  - `_to(pid, method, args)` — отправить одному;
  - `_all(method, args)` — отправить всем;
  - `_sender()` — кто вызвал;
  - `_send_self(pid)` — отправить игроку его полное состояние (`_private`).
- Позицию ведёт клиент, всё остальное (урон, лут, опыт, ресурсы) считает только хост.

**Автозагрузки** (`project.godot`): `Items`, `Rules`, `Save`, `Net`, `Sfx`, `World`. `World.night` — число от 0 до 1, ночь ли сейчас.

**Ключевые файлы:**

| Файл | Что в нём |
|---|---|
| `scripts/rules.gd` | Формулы героя: `stat`, `max_hp`, `damage`, `crit_chance`, `attack_speed`, `armor`, `cd_mult`, `heal_power`, `speed_mult`, `stamina_regen`, `res_max`, `res_regen`, `skill_cost`. Классы `CLASSES`, умения `SKILLS`, базовые атаки `ATTACKS`. Используется и хостом, и клиентом. |
| `scripts/host_skills.gd` | Хост: `hit_enemy()` (один удар по врагу — главная точка для даров боя), `strike()` (удар по кругу), `bolt()` (снаряд), `use()` (умения), `basic_attack()`, ресурсы (`res_tick`, `add_res`, `on_hurt`), опыт (`on_kill`, `give_xp`), `damage_taken_mult()`, баффы `p.buffs[name] = мс_до_конца`. |
| `scripts/host_logic.gd` | Хост: игроки `players[pid]` (словарь героя: `hp`, `max_hp`, `pos`, `equip`, `cls`, `gifts`, `res`, `buffs`, `cds`, `level`…), враги `enemies[eid]` (`kind`, `pos`, `hp`, `max_hp`, `cd`, `slow_until`), `_hurt_player()` (урон по игроку), `_enemy_ai()`, `_kill()` (смерть врага, монеты, лут), `_players_tick()` (регенерация, возрождение). |
| `scripts/gifts.gd` | Каталог даров (static): `Gifts.get_gift(id)`, `Gifts.all()`, `Gifts.roll_fate()`, `Gifts.sanitize()`. Подключается так: `const Gifts := preload("res://scripts/gifts.gd")`. |
| `data/gifts.json` | 250 даров, по одному на строку. |
| `scripts/game.gd` | Клиент: движение, рывок, спринт, выносливость (`move_mult()`, `dash()`, `stamina`), RPC. |
| `scripts/char_window.gd` | Окно героя (C), уже показывает дары. |
| `scripts/debug_autotest.gd` | Автотест, который запускает 2 окна игры и делает скриншоты. |

## Формат дара в `data/gifts.json`

```json
{"id": "berserk", "name": "Берсерк", "rarity": "r", "cat": "combat", "desc": "...",
 "mods": {"dmg": 0.1}, "when": "low_hp", "proc": ["hit", 0.15, "bleed", 0.3], "flag": "berserk"}
```

- `mods` — постоянные добавки. Значение — доля: `0.08` = +8%. Отрицательное — минус. `bag`, `bank` и `dash_charges` — целые числа.
- `when` — условие. Пока оно не выполнено, `mods` этого дара **не действуют**. Без `when` действуют всегда.
- `proc` — срабатывание `[событие, шанс 0..1, эффект, значение]`.
- `flag` — особая механика, у каждого флага своя логика.

У 152 даров нет `flag`: они работают только на `mods`, `when` и `proc`. У 98 даров `flag` есть.

## Баланс: это обязательно

Дары складываются между собой, с расой, классом и вещами. Чтобы сочетания не ломали игру, в `scripts/gifts.gd` уже заданы правила. Движок обязан их соблюдать:

- **`Gifts.CAPS`** — потолки итоговых значений: крит ≤ 60%, уклонение ≤ 35%, перезарядки короче максимум на 40%, вампиризм ≤ 20%, скорость ≤ +45%, урон от даров ≤ +100%, лут, монеты и опыт ≤ ×2 и т.д. Обрезай по ним **итог**, а не каждый дар отдельно.
- **`Gifts.PROC_ICD`** — один и тот же дар срабатывает по событию `hit` не чаще раза в 0.4 с. Иначе быстрое оружие и умения по площади запускают срабатывания десятки раз в секунду.
- **`Gifts.DOT_MAX_STACKS`** — урон со временем копится максимум до 10 раз.
- **`Gifts.BOSS_RULES`** — на боссов (голем) не действуют `instakill`, `execute`, `knockback`, `fear`. Оглушение и замедление по ним в 4 раза короче. Урон со временем — не больше 1% их здоровья в секунду.
- **Уже сделано в коде, не ломай:**
  - `Rules.ENEMY_MIN_DMG` — удар врага после брони не меньше 20% его силы;
  - `Rules.MIN_DMG_TAKEN` — все множители защиты вместе не ниже ×0.15, кроме божественного щита.
  
  Новые защитные дары (`dmg_taken_*`, щиты, броня) тоже должны проходить через эти минимумы.

## Что сделать

### 1. Пассивные добавки (`mods` без `when`) — и на хосте, и на клиенте

Добавь в `gifts.gd` статическую функцию `mod(p: Dictionary, key: String) -> float`. Она суммирует `mods[key]` по всем дарам героя, у которых нет `when`, плюс `mods["all"]` для боевых ключей. Подключи её в формулы `rules.gd`, чтобы окно героя и сервер показывали и считали одно и то же:

| Ключ | Куда подключить |
|---|---|
| `dmg` | множитель в `damage()` |
| `hp` | множитель в `max_hp()` |
| `armor` | множитель в `armor()` |
| `crit` | прибавка в `crit_chance()` |
| `aspd` | в `attack_speed()` |
| `speed` | в `speed_mult()` (движение ведёт клиент — клиент тоже должен это учитывать) |
| `cd` | в `cd_mult()` (−0.12 = на 12% короче) |
| `heal` | в `heal_power()` |
| `mana` | в `res_max()` для маны |
| `mana_regen` | в `res_regen()` |
| `mana_cost` | в `skill_cost()` |
| `stam_regen` | в `stamina_regen()` |
| `hp_regen` | в регенерацию в `host_logic._players_tick` |

Остальные ключи сделай так:
- `crit_dmg` — множитель крита в `hit_enemy` (сейчас ×2).
- `skill_dmg`, `skill_crit` — только для ударов из умений (передай признак в `hit_enemy` через `opts`).
- `aoe` — радиус `strike`/`aoe` у умений.
- `buff_dur` — длительность баффов в `use()`.
- `lifesteal`, `thorns`, `dodge` — в `hit_enemy` и `_hurt_player`.
- `heal_taken` — в `_heal`.
- `dmg_taken_melee`, `dmg_taken_ranged` — пока все враги бьют вблизи, используй `melee`.
- `xp` — в `on_kill`/`give_xp`.
- `coin` — в `_kill` рядом с `coin_mult` расы.
- `loot`, `rare_find`, `mega_rare`, `mythic_find` — в `_kill` и `Items.roll_drop`:
  - `loot` повышает шанс выпадения;
  - `rare_find` сдвигает веса к редким;
  - `mega_rare` и `mythic_find` умножают вес легендарных и мифических.
- `buy_price`, `sell_price` — в `scripts/host_economy.gd`.
- `bag` — `Items.MAX_INV` для этого героя.
- `bank` — `Items.MAX_BANK` для этого героя.
- `sprint_cost`, `sprint_speed`, `dash_cd`, `dash_dist`, `dash_charges` — на клиенте в `game.gd`.
- `parry_cost` — расход выносливости на парирование (клиент, `game.parry()`, `Rules.PARRY.cost`).
- `parry_window` — длина окна парирования (хост, `host_logic.parry()`, `Rules.PARRY.window`).
- `cc_resist`, `dot`, `block`, `food`, `cook`, `pickup`, `chest_coin`, `revive_speed`, `buff_power` — там, где система уже есть. Если системы нет (оглушений игрока пока нет, еды нет), просто оставь ключ без эффекта.

Ключи ремёсел (`gather_*`, `craft_*`, `xp_smith` и т.п., `tool_wear`, `carry`, `salvage`) **пока не трогай**: систем добычи и крафта ещё нет. Сделай одну функцию-заглушку `Gifts.mod(p, "gather_ore")`, которой будущий код сможет пользоваться.

### 2. Условия (`when`) — только на хосте

Создай `scripts/host_gifts.gd` (Node, `var host`, создаётся в `host_logic._ready()` рядом с `skills`). Функция `cond(pid, when, ctx) -> bool`, где `ctx` — словарь с текущей целью и оружием.

| Условие | Значение |
|---|---|
| `low_hp` | здоровье < 35% |
| `still` | не двигался 0.5 с (позиция в `update_pos`) |
| `night` | `World.night > 0.5` |
| `day` | `World.night < 0.5` |
| `group` | рядом союзник в 200 |
| `near_ally` | союзник в 80 |
| `outnumbered` | 3+ врага в 120 |
| `one_enemy` | ровно 1 враг в 120 |
| `target_low` | у цели < 50% |
| `vs_slime`, `vs_wolf`, `vs_golem` | вид цели |
| `vs_big` | голем |
| `vs_elite` | голем |
| `vs_undead` | пока false |
| `blade` | меч, кинжал или клинок бездны |
| `blunt` | молот |
| `far_target` | цель дальше 120 |
| `not_hurt3` | 3 с без урона |
| `on_road` | пока false |
| `in_forest` | пока false |
| `dungeon` | пока false |

Добавки даров с `when` применяй на хосте в момент удара или урона: `hit_enemy`, `_hurt_player`, регенерация.

### 3. Срабатывания (`proc`) — только на хосте

В `host_gifts.gd` сделай `fire(pid, event, ctx)`. Вызывай её из нужных мест.

**События:**

| Событие | Откуда вызывать |
|---|---|
| `hit` | после каждого `hit_enemy` |
| `kill` | `_kill` |
| `hurt` | `_hurt_player` |
| `dodge` | когда сработало уклонение |
| `parry` | удачное парирование: ветка с `parry_until` в `host_logic._hurt_player` |
| `skill` | в конце `use()` |
| `dash` | `host_logic.dash()` |
| `low_hp` | при переходе ниже 35%, один раз до восстановления выше |
| `combat_start` | первый удар после 5 с без боя |
| `combat_end` | 5 с без боя после боя |
| `death` | смерть игрока |
| `tick` | раз в секунду |

**Эффекты** (значение берётся из 4-го элемента `proc`):

| Эффект | Что делает |
|---|---|
| `buff_dmg`, `buff_aspd`, `buff_speed` | временный бафф на 4 с |
| `stack_dmg` | накапливаемый бафф урона на 5 с, максимум +50% |
| `next_hit_mult` | следующий удар умножается |
| `bleed`, `poison`, `burn` | урон со временем по врагу: доля урона героя в секунду, 4 с. Сделай систему DoT у врагов в `host_logic`, тики раз в 0.5 с, через `c_enemy_hit`. |
| `bleed_stack` | DoT накапливается без предела |
| `burn_near` | поджигает врагов вокруг |
| `stun` | враг не ходит и не бьёт N с: `e.stun_until` в `_enemy_ai` |
| `slow` | `e.slow_until` уже есть |
| `knockback` | оттолкнуть врага на N через `World.move` |
| `weaken` | враг бьёт слабее на 5 с |
| `sunder` | враг получает больше урона на 5 с |
| `repeat` | повторить тот же удар |
| `whirl` | удар по кругу радиусом 46 |
| `quake` | удар по кругу 60 с долей урона |
| `chain` | молния в N ближайших врагов с `c_shot` вида `"arcane"` |
| `instakill` | убить, если не голем |
| `mana` | вернуть долю `res_max` |
| `repeat_skill` | бесплатно повторить умение |
| `cd_reset` | обнулить перезарядку умения |
| `cd_all` | сократить все перезарядки на N с |
| `heal` | лечение долей max_hp |
| `heal_allies` | лечение союзников рядом долей их max_hp |
| `delayed_heal` | вернуть долю полученного урона через 3 с |
| `shield_from_dmg` | щит из доли нанесённого урона: новое поле `p.shield`, его съедает урон в `_hurt_player`; отправь клиенту, покажи в HUD тонкой белой полоской поверх HP |
| `invuln` | неуязвимость N с через `invuln_until` |
| `self_dmg` | урон себе долей max_hp, не ниже 1 HP |
| `coin_mult` | монет ×N с этого убийства |
| `gold_drop` | дополнительная кучка монет |
| `dash_dmg` | урон врагам на пути рывка |
| `reflect` | при парировании вернуть врагу N× урона его удара |
| `parry_reset` | при парировании сразу снять перезарядку парирования (`p.parry_ready = 0`), ответный удар ×N вместо `Rules.PARRY.riposte` |

Эффекты `double`, `gem`, `free_craft`, `no_deplete`, `rare_mat`, `golden_item`, `decoy`, `summon_wolf` пропусти: для них нет систем. Помечай пропущенное в `docs/codex/gifts_status.md` (см. ниже).

### 4. Флаги (`flag`)

Сделай **только эти** 31 флаг. Они опираются на то, что уже есть в игре:

`berserk`, `first_crit`, `cleave`, `momentum`, `combo4`, `execute15`, `crit_chain`, `echo5`, `kill_streak`, `fate_blade`, `cheat_death300`, `self_revive600`, `diamond3`, `dmg_cap25`, `block30`, `mana_shield10`, `overheal_shield`, `heal_splash`, `empath`, `mana_scaling`, `random_dmg`, `no_armor`, `lone_wolf`, `lunatic`, `night_owl`, `coward`, `hp_cost`, `no_heal`, `free_sprint`, `any_weapon`, `counter_parry` (у дара «Ответный удар» `proc` срабатывает и на событие `parry`, не только на `dodge`).

Описание каждого — поле `desc` того же дара в JSON, делай по нему. Счётчики (`momentum`, `crit_chain`, `fate_blade` и т.п.) храни в словаре героя на хосте. Если счётчик должен переживать выход из игры (`fate_blade`, позже `devourer`), сохраняй его в новом поле `gift_state`: `save.gd` → `sanitize_char`, `game.gd` → `Save.store_char`, `host_logic._private`.

Остальные флаги не делай, только перечисли их в отчёте.

### 5. Проверка

1. Создай `tests/test_gifts.gd` (`extends SceneTree`). Запуск:
   ```
   "<godot>" --headless --path C:\Users\isi08\Desktop\coop-rpg --script res://tests/test_gifts.gd
   ```
   Тест должен:
   - убедиться, что у **каждого** из 250 даров:
     - все ключи `mods` известны: либо подключены, либо в списке «отложено до ремёсел»;
     - `when` из списка условий;
     - событие и эффект `proc` из списков;
     - `flag` либо реализован, либо в списке отложенных;
   - для нескольких даров (`strong_arm`, `glass_cannon`, `fortress`, `archmage`, `swift`) проверить, что `Rules.damage`, `max_hp`, `skill_cost` и `speed_mult` реально меняются у героя-словаря с этим даром и без него;
   - проверить потолки: герой с дарами `precision` + `sharp_eye` + `four_leaf` + `lucky` и ловкостью 300 не получает крит выше 60%;
   - выйти с кодом 1 при любой ошибке и напечатать, что не так.
2. Запусти обычный автотест двумя окнами. Окна запускай свёрнутыми и закрывай после. **Закрывай только процессы Godot, в командной строке которых есть `coop-rpg`. Чужие окна Godot (редактор пользователя) не трогай.**
   ```
   хост:  "<godot>" --path <проект> -- --host --autotest --shots=<папка> --name=ТестА --fresh --cls=warrior --gifts=berserk,vampiric --day --winsize=1280x720
   гость: "<godot>" --path <проект> -- --join --autotest --shots=<папка> --name=ТестБ --fresh --cls=mage --gifts=archmage --day --winsize=1280x720
   ```
   В выводе хоста не должно быть `SCRIPT ERROR` и `ERROR`. Строки `[autotest] герой: …` и `[autotest] гость: …` должны появиться.
3. Перед каждым запуском игры после правок кода или ассетов выполни:
   ```
   "<godot>" --headless --path <проект> --import
   ```

## Правила

- Работай в ветке `codex/gifts-engine`: `git checkout -b codex/gifts-engine`. Делай коммиты по шагам, **не пушь** и не сливай в `master`.
- Не меняй:
  - баланс и данные классов, умений и парирования (`CLASSES`, `SKILLS`, `ATTACKS`, `PARRY` в `rules.gd`);
  - меню создания героя (`menu.gd`);
  - графику (`tools/art`, `assets`);
  - сам каталог `data/gifts.json`.
  
  Исключение для каталога: дар описан так, что его нельзя сделать без новой большой системы. Тогда не меняй его, а запиши в отчёт.
- Код в стиле проекта:
  - табы;
  - комментарии и тексты игроку на русском;
  - `##` перед функцией — короткое описание;
  - файлы не длиннее ~500 строк. `game.gd` уже длиннее: новую логику клиента выноси в отдельный файл, а не добавляй туда.
- Всё, что влияет на исход боя, лут и деньги, считай **на хосте**. Клиенту — только показывать и двигаться.
- Не трогай папку `C:\Users\isi08\Desktop\gadot game`: это другой проект.

## Что сдать

1. Ветку `codex/gifts-engine` с коммитами.
2. Файл `docs/codex/gifts_status.md` — таблицу из трёх групп:
   - работает;
   - отложено (ждёт системы добычи, крафта, подземелий, спутников);
   - не сделано и почему.
   
   По каждому дару одна строка: `id`, название, статус.
3. В последнем сообщении:
   - сколько даров работает полностью;
   - вывод `tests/test_gifts.gd`;
   - есть ли ошибки в автотесте.
