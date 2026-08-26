extends Node

const Catalog = preload("res://supabase/one_gun_catalog.gd")
const RewardCalculator = preload("res://match_reward_calculator.gd")
const WinnersResult = preload("res://winners_circle_match_result.gd")

# Owns One Gun's seasonal progression/catalog extensions while SupabaseManager
# remains the authentication, wallet, inventory, and base loadout boundary.
# Every write is an authenticated RPC; clients never calculate persistent
# balances or trust remote peers with Supabase identity/session data.

const REWARD_POLL_ATTEMPTS := 12
const REWARD_POLL_SECONDS := 1.0

signal catalog_updated(items: Array)
signal favorites_updated(item_ids: Array)
signal usage_updated(usage: Dictionary)
signal progression_updated(snapshot: Dictionary)
signal match_reward_updated(receipt: Dictionary)
signal operation_failed(operation: String, message: String)

var catalog_items: Array[Dictionary] = []
var bundle_components: Dictionary = {}
var favorites: Dictionary = {}
var usage: Dictionary = {}
var progression: Dictionary = {}
var last_match_reward: Dictionary = {}

var _backend: Node
var _refresh_in_progress := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("dedicated_server"):
		return
	_backend = get_node_or_null("/root/SupabaseManager")
	if _backend == null:
		return
	_backend.login_state_changed.connect(_on_login_state_changed)
	_backend.shop_loaded.connect(_on_base_shop_loaded)
	_backend.inventory_updated.connect(_on_inventory_updated)
	if _backend.is_authenticated():
		call_deferred("refresh_all")


func is_ready() -> bool:
	return _backend != null and _backend.is_authenticated()


func refresh_all() -> bool:
	if _refresh_in_progress or not is_ready():
		return false
	_refresh_in_progress = true
	var success := true
	success = await load_catalog() and success
	success = await load_bundle_components() and success
	success = await load_favorites() and success
	success = await load_usage() and success
	success = await load_progression() and success
	_refresh_in_progress = false
	return success


func load_catalog() -> bool:
	if not is_ready():
		catalog_items.clear()
		catalog_updated.emit([])
		return false
	var columns := "id,display_name,item_type,description,price,rarity,purchasable," \
		+ "shop_visible,active,category,subcategory,featured,rotation_scope," \
		+ "rotation_starts_at,rotation_ends_at,purchase_count,sort_order,created_at"
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/shop_items?active=eq.true&select=%s&order=sort_order.asc,display_name.asc" \
			% columns)
	if not bool(response.get("ok", false)):
		_fail("catalog", _message(response, "Could not load the Prize Counter catalog."))
		return false
	catalog_items.clear()
	var seen := {}
	var rows = response.get("data", [])
	if rows is Array:
		for value in rows:
			if not value is Dictionary:
				continue
			var item: Dictionary = Catalog.normalize_item(value)
			var item_id := str(item.get("id", ""))
			if item_id == "" or seen.has(item_id):
				continue
			seen[item_id] = true
			catalog_items.append(item)
	catalog_updated.emit(catalog_items.duplicate(true))
	return true


func load_bundle_components() -> bool:
	if not is_ready():
		bundle_components.clear()
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/shop_bundle_items?select=bundle_id,item_id,display_order" \
		+ "&order=display_order.asc")
	if not bool(response.get("ok", false)):
		_fail("bundles", _message(response, "Could not load outfit components."))
		return false
	bundle_components.clear()
	var rows = response.get("data", [])
	if rows is Array:
		for row in rows:
			if not row is Dictionary:
				continue
			var bundle_id := str(row.get("bundle_id", ""))
			var component_id := str(row.get("item_id", ""))
			if bundle_id == "" or component_id == "":
				continue
			if not bundle_components.has(bundle_id):
				bundle_components[bundle_id] = []
			bundle_components[bundle_id].append(component_id)
	return true


func load_favorites() -> bool:
	if not is_ready():
		favorites.clear()
		favorites_updated.emit([])
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/player_favorites?select=item_id&order=created_at.desc")
	if not bool(response.get("ok", false)):
		_fail("favorites", _message(response, "Could not load favorites."))
		return false
	favorites.clear()
	var rows = response.get("data", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary:
				var item_id := str(row.get("item_id", ""))
				if item_id != "":
					favorites[item_id] = true
	favorites_updated.emit(favorite_item_ids())
	return true


func load_usage() -> bool:
	if not is_ready():
		usage.clear()
		usage_updated.emit({})
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/player_item_usage?select=item_id,equip_count,last_equipped_at")
	if not bool(response.get("ok", false)):
		_fail("usage", _message(response, "Could not load item usage."))
		return false
	usage.clear()
	var rows = response.get("data", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary:
				var item_id := str(row.get("item_id", ""))
				if item_id != "":
					usage[item_id] = row.duplicate(true)
	usage_updated.emit(usage.duplicate(true))
	return true


func load_progression() -> bool:
	if not is_ready():
		progression.clear()
		progression_updated.emit({})
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/rpc/get_player_progression", HTTPClient.METHOD_POST, {})
	if not bool(response.get("ok", false)):
		_fail("progression", _message(response, "Could not load seasonal progression."))
		return false
	progression = _response_object(response)
	progression_updated.emit(progression.duplicate(true))
	return true


func item(item_id: String) -> Dictionary:
	for value in catalog_items:
		if str(value.get("id", "")) == item_id:
			return value.duplicate(true)
	return _backend.catalog_item(item_id) if _backend != null else {}


func components_for(bundle_id: String) -> Array[String]:
	var result: Array[String] = []
	var values = bundle_components.get(bundle_id, [])
	if values is Array:
		for value in values:
			result.append(str(value))
	return result


func is_favorite(item_id: String) -> bool:
	return favorites.has(item_id)


func favorite_item_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id in favorites:
		result.append(str(item_id))
	result.sort()
	return result


func usage_count(item_id: String) -> int:
	var record = usage.get(item_id, {})
	return int(record.get("equip_count", 0)) if record is Dictionary else 0


func set_favorite(item_id: String, favorite: bool) -> bool:
	if not is_ready():
		_fail("favorite", "Sign in to save favorites.")
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/rpc/set_shop_favorite", HTTPClient.METHOD_POST,
		{"p_item_id": item_id, "p_favorite": favorite})
	if not bool(response.get("ok", false)):
		_fail("favorite", _message(response, "Could not update this favorite."))
		return false
	if favorite:
		favorites[item_id] = true
	else:
		favorites.erase(item_id)
	favorites_updated.emit(favorite_item_ids())
	return true


func purchase_item(item_id: String) -> bool:
	if _backend == null:
		return false
	var success: bool = await _backend.purchase_shop_item(item_id)
	if success:
		await refresh_all()
	return success


func equip_item(slot: String, item_id: String) -> bool:
	if _backend == null:
		return false
	var success: bool = await _backend.equip_cosmetic(slot, item_id)
	if success:
		await load_usage()
	return success


func equip_outfit(bundle_id: String) -> bool:
	if not is_ready():
		_fail("equip_outfit", "Sign in to equip an outfit.")
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/rpc/equip_outfit", HTTPClient.METHOD_POST,
		{"p_bundle_id": bundle_id})
	if not bool(response.get("ok", false)):
		_fail("equip_outfit", _message(response, "Could not equip this outfit."))
		return false
	await _backend.load_loadout()
	await load_usage()
	return true

func unequip_outfit(bundle_id: String) -> bool:
	if not is_ready():
		_fail("unequip_outfit", "Sign in to unequip an outfit.")
		return false
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/rpc/unequip_outfit", HTTPClient.METHOD_POST,
		{"p_bundle_id": bundle_id})
	if not bool(response.get("ok", false)):
		_fail("unequip_outfit", _message(response, "Could not unequip this outfit."))
		return false
	return await _backend.load_loadout()


func reset_loadout() -> bool:
	if _backend == null:
		return false
	var success: bool = await _backend.reset_cosmetic_loadout()
	if success:
		await load_usage()
	return success



func confirm_official_match(result: Dictionary, actor_id: int,
		claim_secret: String) -> Dictionary:
	var confirmation_result := WinnersResult.confirmation_payload(result)
	last_match_reward = RewardCalculator.preview_for_actor(
		confirmation_result, actor_id)
	last_match_reward["state"] = "verifying"
	match_reward_updated.emit(last_match_reward.duplicate(true))
	if not is_ready():
		last_match_reward["state"] = "sign_in_required"
		last_match_reward["message"] = "Sign in to bank official rewards."
		match_reward_updated.emit(last_match_reward.duplicate(true))
		return last_match_reward
	if not bool(confirmation_result.get("official", false)):
		last_match_reward["state"] = "not_official"
		last_match_reward["message"] = "This match did not use the Official Beta rules."
		match_reward_updated.emit(last_match_reward.duplicate(true))
		return last_match_reward
	var response: Dictionary = await _backend._authenticated_request(
		"/rest/v1/rpc/confirm_official_beta_match", HTTPClient.METHOD_POST,
		{
			"p_match_id": str(confirmation_result.get("match_id", "")),
			"p_actor_id": actor_id,
			"p_claim_secret": claim_secret,
			"p_result": confirmation_result,
		})
	if not bool(response.get("ok", false)):
		last_match_reward["state"] = "error"
		last_match_reward["message"] = _message(response, "Reward verification failed.")
		_fail("match_reward", str(last_match_reward["message"]))
		match_reward_updated.emit(last_match_reward.duplicate(true))
		return last_match_reward
	var receipt := _response_object(response)
	last_match_reward = RewardCalculator.merge_receipt(last_match_reward, receipt)
	match_reward_updated.emit(last_match_reward.duplicate(true))
	if str(last_match_reward.get("state", "")) != "settled":
		await _poll_match_reward(str(confirmation_result.get("match_id", "")), actor_id)
	else:
		await _refresh_after_reward()
	return last_match_reward


func _poll_match_reward(match_id: String, _actor_id: int) -> void:
	for attempt in REWARD_POLL_ATTEMPTS:
		await get_tree().create_timer(REWARD_POLL_SECONDS, true, false, true).timeout
		if not is_ready():
			return
		var response: Dictionary = await _backend._authenticated_request(
			"/rest/v1/rpc/get_official_match_reward", HTTPClient.METHOD_POST,
			{"p_match_id": match_id})
		if not bool(response.get("ok", false)):
			continue
		last_match_reward = RewardCalculator.merge_receipt(
			last_match_reward, _response_object(response))
		match_reward_updated.emit(last_match_reward.duplicate(true))
		if str(last_match_reward.get("state", "")) == "settled":
			await _refresh_after_reward()
			return
	last_match_reward["state"] = "pending"
	last_match_reward["message"] = "Waiting for the other players to confirm the result."
	match_reward_updated.emit(last_match_reward.duplicate(true))


func _refresh_after_reward() -> void:
	await _backend.load_currency()
	await _backend.load_inventory()
	await refresh_all()


func _response_object(response: Dictionary) -> Dictionary:
	var data = response.get("data", {})
	if data is Dictionary:
		return data.duplicate(true)
	if data is Array and not data.is_empty() and data[0] is Dictionary:
		return data[0].duplicate(true)
	return {}


func _message(response: Dictionary, fallback: String) -> String:
	if _backend != null and _backend.has_method("_response_message"):
		return str(_backend._response_message(response, fallback))
	return fallback


func _fail(operation: String, message: String) -> void:
	operation_failed.emit(operation, message)
	push_warning("ProgressionManager %s: %s" % [operation, message])


func _on_login_state_changed(state: String) -> void:
	if state == "authenticated":
		call_deferred("refresh_all")
	elif state == "logged_out":
		catalog_items.clear()
		bundle_components.clear()
		favorites.clear()
		usage.clear()
		progression.clear()
		last_match_reward.clear()
		catalog_updated.emit([])
		favorites_updated.emit([])
		usage_updated.emit({})
		progression_updated.emit({})


func _on_base_shop_loaded(_items: Array) -> void:
	if is_ready() and not _refresh_in_progress:
		call_deferred("load_catalog")


func _on_inventory_updated(_items: Array) -> void:
	if is_ready() and not _refresh_in_progress:
		call_deferred("load_catalog")
