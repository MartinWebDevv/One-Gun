extends Node

# Keeps official-match reward proof separate from NetworkManager's gameplay
# roster. A player owns a private random secret for the signed-in app session;
# only its SHA-256 hash crosses ENet. Supabase identity and session tokens never
# enter peer traffic.

signal reward_identity_changed

var _local_claim_secret := ""
var _peer_claim_hashes: Dictionary = {}
var _sync_generation := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("dedicated_server"):
		return
	SupabaseManager.login_state_changed.connect(_on_login_state_changed)
	NetworkManager.lobby_changed.connect(_on_lobby_changed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if SupabaseManager.is_authenticated():
		_refresh_local_identity()


func local_claim_secret() -> String:
	return _local_claim_secret


func local_claim_hash() -> String:
	return _local_claim_secret.sha256_text() if _local_claim_secret != "" else ""


func peer_claim_hash(peer_id: int) -> String:
	if peer_id == NetworkManager.local_id():
		return local_claim_hash()
	return str(_peer_claim_hashes.get(peer_id, ""))


func all_participants_ready(peer_ids: Array, minimum_participants := 3) -> bool:
	if peer_ids.size() < minimum_participants:
		return false
	for peer_id_value in peer_ids:
		if peer_claim_hash(int(peer_id_value)) == "":
			return false
	return true


func new_match_receipt_id() -> String:
	if not NetworkManager.is_host():
		return ""
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _refresh_local_identity() -> void:
	_sync_generation += 1
	_peer_claim_hashes.clear()
	_local_claim_secret = Crypto.new().generate_random_bytes(24).hex_encode()
	reward_identity_changed.emit()
	_sync_with_host.call_deferred(_sync_generation)


func _clear_identity() -> void:
	_sync_generation += 1
	_local_claim_secret = ""
	_peer_claim_hashes.clear()
	reward_identity_changed.emit()


func _sync_with_host(generation: int) -> void:
	if generation != _sync_generation or not NetworkManager.is_online() \
			or local_claim_hash() == "":
		return
	if NetworkManager.is_host():
		_peer_claim_hashes[NetworkManager.local_id()] = local_claim_hash()
		reward_identity_changed.emit()
		return
	# The NetworkManager compatibility handshake can still be settling when its
	# first lobby_changed signal arrives, so retry a few cheap reliable sends.
	for attempt in 5:
		if generation != _sync_generation or not NetworkManager.is_online():
			return
		_submit_claim_hash.rpc_id(1, local_claim_hash())
		await get_tree().create_timer(0.5, true, false, true).timeout


@rpc("any_peer", "reliable")
func _submit_claim_hash(raw_hash: String) -> void:
	if not NetworkManager.is_host() or NetworkManager.lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not NetworkManager.peers.has(sender):
		return
	var safe_hash := _sanitize_hash(raw_hash)
	if safe_hash == "":
		return
	_peer_claim_hashes[sender] = safe_hash
	reward_identity_changed.emit()


func _sanitize_hash(value: String) -> String:
	var cleaned := value.strip_edges().to_lower()
	if cleaned.length() != 64:
		return ""
	for character in cleaned:
		if character not in "0123456789abcdef":
			return ""
	return cleaned


func _on_login_state_changed(state: String) -> void:
	if state == "authenticated":
		_refresh_local_identity()
	elif state == "logged_out":
		_clear_identity()


func _on_lobby_changed() -> void:
	if not NetworkManager.is_online():
		_peer_claim_hashes.clear()
		return
	if NetworkManager.is_host():
		if local_claim_hash() != "" and not NetworkManager.is_dedicated_server():
			_peer_claim_hashes[NetworkManager.local_id()] = local_claim_hash()
		for peer_id in _peer_claim_hashes.keys():
			if not NetworkManager.peers.has(peer_id):
				_peer_claim_hashes.erase(peer_id)
		reward_identity_changed.emit()
	elif local_claim_hash() != "":
		_sync_generation += 1
		_sync_with_host.call_deferred(_sync_generation)


func _on_peer_disconnected(peer_id: int) -> void:
	if _peer_claim_hashes.erase(peer_id):
		reward_identity_changed.emit()
