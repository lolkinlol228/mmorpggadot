extends Node
## Подключение: хост создаёт ENet-сервер, остальные подключаются по IP.
## Позже сюда же можно добавить Steam (GodotSteam) — остальной код менять не придётся.

const DEFAULT_PORT := 7777
const MAX_PEERS := 7

var player_name := "Герой"
var player_look := {}
var player_class := "warrior"      # выбран в создании героя (действует только для нового героя)
var player_gifts: Array = []        # дары, выпавшие в создании героя
var port := DEFAULT_PORT
var last_error := ""
var args_applied := false


func host(p: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, MAX_PEERS)
	if err != OK:
		return err
	port = p
	multiplayer.multiplayer_peer = peer
	return OK


func join(ip: String, p: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p)
	if err != OK:
		return err
	port = p
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
