extends RefCounted
## Общий таймер зарядов рывка для клиента и хоста.

const Gifts := preload("res://scripts/gifts.gd")
var used: Array[int] = []
var last_at := -1000


## Тратит заряд, если истёк предыдущий рывок и доступно восстановление.
func consume(p: Dictionary, free: bool) -> bool:
	var now := Time.get_ticks_msec()
	if now - last_at < 200:
		return false
	var cooldown := maxi(200, int(260.0 * Gifts.factor(p, "dash_cd")))
	while not used.is_empty() and used.front() <= now:
		used.pop_front()
	if not free:
		if used.size() >= maxi(1, 1 + int(Gifts.mod(p, "dash_charges"))):
			return false
		used.append(now + cooldown)
	last_at = now
	return true
