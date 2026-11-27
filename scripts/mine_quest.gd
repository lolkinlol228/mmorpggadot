extends RefCounted

const EVENTS := ["fisher", "smith", "shell", "interrupt", "warden"]
const GOALS := [1, 1, 3, 2, 1]
const TASKS := ["Расспросить Рыбака у Пристани", "Показать Горну осколок ядра",
	"Победить панцирников", "Прервать звон звонаря", "Победить Колокольного Стража"]

static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		raw = {}
	var step := clampi(int(raw.step), 0, 5) if raw.get("step") is float or raw.get("step") is int else 0
	var count := 0
	if step < 5 and (raw.get("count") is int or raw.get("count") is float):
		count = clampi(int(raw.count), 0, GOALS[step] - 1)
	return {"step": step, "count": count, "golem": raw.get("golem") == true}


static func progress(q: Dictionary, event: String) -> bool:
	if q.step >= EVENTS.size() or EVENTS[q.step] != event:
		return false
	q.count += 1
	if q.count >= GOALS[q.step]:
		q.step += 1
		q.count = 0
	return true


static func objective(q: Dictionary) -> String:
	if q.step >= EVENTS.size():
		return "Колокольный Страж побеждён"
	return "%d/5 · %s (%d/%d)" % [q.step + 1, TASKS[q.step], q.count, GOALS[q.step]]


static func has_shard(p: Dictionary) -> bool:
	return p.inv.any(func(item): return item.base == "golem_shard")


static func dialogue(actor: String, opened: bool, p: Dictionary) -> String:
	var q: Dictionary = p.quests
	if actor == "fisher":
		if not opened:
			return "Раньше здесь была шахта. Пока Голем жив, её вход под водой."
		var news := "Твоя победа осушила ход!" if q.golem else "Пока тебя не было, пал Голем. Вода ушла, смотри — открылся проход!"
		return news + " Горн в Пепельном Броде узнает руду. Покажи ему осколок ядра."
	if not opened or q.step == 0:
		return "После гибели Голема расспроси Рыбака у Пристани. Потом принеси мне осколок ядра."
	if q.step == 1 and not has_shard(p):
		return "Осколок падает с Голема каждому участнику. Его также можно выменять у товарища."
	return "Это руда из затопленной шахты! У моего верстака обменяй осколок на свойство оружия. Бери друзей и ищи панцирников в проходе у Пристани."
