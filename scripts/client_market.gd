extends RefCounted
## Клиент отправляет намерение, а подтверждённое состояние рынка получает от хоста.

var game
var data := {}


## Передаёт запрос без локального изменения денег и инвентаря.
func request(op: String, arguments: Dictionary = {}) -> void:
	game._to_host("h_market", [op, arguments])


## Сохраняет последнюю страницу и обновляет открытое окно.
func receive(value: Dictionary) -> void:
	data = value
	game.ui.market.receive(value)
