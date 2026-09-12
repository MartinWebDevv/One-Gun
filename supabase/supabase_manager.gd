extends Node

const Catalog = preload("res://supabase/one_gun_catalog.gd")

# Client-only Supabase REST/Auth integration. The configured key must be a
# client-safe publishable/anon credential protected by Row Level Security.
# A Supabase secret/service-role/admin key must never be shipped here.

const CONFIG_PATH := "res://supabase/supabase_config.json"
const SESSION_PATH := "user://supabase_session.json"
const SESSION_TEMP_PATH := "user://supabase_session.pending.json"
const REQUEST_TIMEOUT_SECONDS := 15.0
const REFRESH_MARGIN_SECONDS := 60
const ACCOUNT_NAME_MIN_LENGTH := 3
const ACCOUNT_NAME_MAX_LENGTH := 20
const ACCOUNT_RENAME_COOLDOWN_SECONDS := 14 * 24 * 60 * 60

signal configuration_loaded(configured: bool, message: String)
signal login_state_changed(state: String)
signal login_succeeded(user_id: String)
signal login_failed(message: String)
signal account_created(message: String)
signal account_creation_failed(message: String)
signal logout_completed
signal account_name_changed(username: String)
signal account_name_change_failed(message: String)
signal profile_loaded(profile: Dictionary)
signal currency_updated(gun_tokens: int)
signal inventory_updated(inventory: Array)
signal shop_loaded(items: Array)
signal loadout_updated(loadout: Dictionary)
signal purchase_succeeded(item_id: String)
signal purchase_failed(item_id: String, message: String)
signal equip_succeeded(slot: String, item_id: String)
signal equip_failed(slot: String, item_id: String, message: String)
signal unequip_succeeded(slot: String)
signal unequip_failed(slot: String, message: String)
signal loadout_reset_succeeded
signal loadout_reset_failed(message: String)
signal backend_error(operation: String, message: String)
signal initial_data_loaded(success: bool)
signal session_refresh_finished(success: bool)

var project_url := ""
var publishable_key := ""
var access_token := ""
var refresh_token := ""
var authenticated_user_id := ""
var access_token_expires_at := 0
var login_state := "logged_out"
var _auth_username_claim := ""

var profile: Dictionary = {}
var gun_tokens := 0
var inventory: Array[Dictionary] = []
var shop_items: Array[Dictionary] = []
var loadout: Dictionary = SupabaseCosmeticRegistry.empty_loadout()

var _owned_item_ids: Dictionary = {}
var _purchase_in_flight: Dictionary = {}
var _refresh_in_progress := false
var _initial_load_in_progress := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Dedicated gameplay servers have no account/store UI and must not ship or
	# contact a player-facing Supabase project. Automated peers must not restore
	# or rotate the actual player's saved sign-in session either.
	if OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--hideout-test"):
		return
	_load_configuration()
	call_deferred("_restore_session")


func is_configured() -> bool:
	return project_url != "" and publishable_key != ""


func is_authenticated() -> bool:
	return access_token != "" and refresh_token != "" \
		and authenticated_user_id != ""


func has_valid_access_token_shape() -> bool:
	# Social presence starts polling continuously as soon as an account is live.
	# Reject incomplete/corrupt bearer tokens at that boundary instead of sending
	# them to PostgREST and triggering a refresh race with unrelated local state.
	var parts := access_token.split(".")
	return parts.size() == 3 \
		and not str(parts[0]).is_empty() \
		and not str(parts[1]).is_empty() \
		and not str(parts[2]).is_empty()


func current_user_id() -> String:
	return authenticated_user_id


func owns_item(item_id: String) -> bool:
	return _owned_item_ids.has(SupabaseCosmeticRegistry.sanitize_item_id(item_id))


func owned_item_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id in _owned_item_ids:
		result.append(str(item_id))
	result.sort()
	return result


func equipped_cosmetics() -> Dictionary:
	return loadout.duplicate(true)


func catalog_item(item_id: String) -> Dictionary:
	var safe_id := SupabaseCosmeticRegistry.sanitize_item_id(item_id)
	for item in shop_items:
		if str(item.get("id", "")) == safe_id:
			return item.duplicate(true)
	return SupabaseCosmeticRegistry.local_catalog_item(safe_id)


func create_account(email: String, password: String, username: String) -> bool:
	var username_error := account_name_error(username)
	if username_error != "":
		account_creation_failed.emit(username_error)
		return false
	var safe_username := sanitize_account_name(username)
	if not _can_start_auth(email, password):
		return false
	_set_login_state("authenticating")
	var response: Dictionary = await _request(
		"/auth/v1/signup", HTTPClient.METHOD_POST,
		{
			"email": email.strip_edges(),
			"password": password,
			"data": {"username": safe_username},
		}, false)
	if not bool(response.get("ok", false)):
		var message := _response_message(response, "Account creation failed.")
		_set_login_state("logged_out")
		account_creation_failed.emit(message)
		return false
	var data = response.get("data", {})
	if data is Dictionary and str(data.get("access_token", "")) != "":
		if not _accept_auth_response(data):
			account_creation_failed.emit("Supabase returned an incomplete session.")
			return false
		account_created.emit("Account created and signed in.")
		login_succeeded.emit(authenticated_user_id)
		await load_all_player_data()
		await _claim_username_from_auth_metadata()
		return true
	_set_login_state("logged_out")
	account_created.emit(
		"Account created for %s. Check your email to confirm it, then sign in." \
			% safe_username)
	return true


func sign_in(email: String, password: String) -> bool:
	if not _can_start_auth(email, password):
		return false
	_set_login_state("authenticating")
	var response: Dictionary = await _request(
		"/auth/v1/token?grant_type=password", HTTPClient.METHOD_POST,
		{"email": email.strip_edges(), "password": password}, false)
	if not bool(response.get("ok", false)):
		var message := _response_message(response, "Sign in failed.")
		_set_login_state("logged_out")
		login_failed.emit(message)
		return false
	if not _accept_auth_response(response.get("data", {})):
		_set_login_state("logged_out")
		login_failed.emit("Supabase returned an incomplete session.")
		return false
	login_succeeded.emit(authenticated_user_id)
	await load_all_player_data()
	await _claim_username_from_auth_metadata()
	return true


func sign_out() -> void:
	var social_manager := get_node_or_null("/root/SocialManager")
	if social_manager != null and social_manager.has_method("clear_presence"):
		await social_manager.clear_presence()
	if is_authenticated() and is_configured():
		await _request("/auth/v1/logout", HTTPClient.METHOD_POST, {}, true)
	_clear_runtime_session(true)
	logout_completed.emit()


func load_all_player_data() -> bool:
	if _initial_load_in_progress or not is_authenticated():
		return false
	_initial_load_in_progress = true
	_set_login_state("loading_data")
	var success := true
	success = await load_profile() and success
	success = await load_currency() and success
	success = await load_inventory() and success
	success = await load_loadout() and success
	success = await load_shop() and success
	_initial_load_in_progress = false
	_set_login_state("authenticated" if is_authenticated() else "logged_out")
	initial_data_loaded.emit(success)
	return success


func sanitize_account_name(value: String) -> String:
	var source := value.strip_edges().substr(0, ACCOUNT_NAME_MAX_LENGTH)
	var cleaned := ""
	for character in source:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			cleaned += character
	return cleaned


func current_account_name() -> String:
	var raw_username = profile.get("username", "")
	if raw_username == null:
		return ""
	var username := str(raw_username).strip_edges()
	if username.to_lower() in ["null", "<null>"]:
		return ""
	return username


func account_name_error(value: String) -> String:
	var source := value.strip_edges()
	if source.length() < ACCOUNT_NAME_MIN_LENGTH:
		return "Account Name must be at least %d characters." % ACCOUNT_NAME_MIN_LENGTH
	if source.length() > ACCOUNT_NAME_MAX_LENGTH:
		return "Account Name cannot exceed %d characters." % ACCOUNT_NAME_MAX_LENGTH
	var cleaned := sanitize_account_name(source)
	if cleaned != source:
		return "Use only letters, numbers, and underscores in the Account Name."
	if cleaned.begins_with("_"):
		return "Account Name must begin with a letter or number."
	return ""


func rename_account_name(username: String) -> bool:
	var safe_username := sanitize_account_name(username)
	var validation_error := account_name_error(username)
	if validation_error != "":
		account_name_change_failed.emit(validation_error)
		return false
	if not is_authenticated():
		account_name_change_failed.emit("Sign in before renaming the account.")
		return false
	var is_initial_claim := current_account_name() == ""
	var rpc_name := "claim_profile_username" if is_initial_claim \
		else "rename_profile_username"
	var response := await _authenticated_request(
		"/rest/v1/rpc/%s" % rpc_name, HTTPClient.METHOD_POST,
		{"p_username": safe_username})
	if not bool(response.get("ok", false)):
		var message := _response_message(response,
			"Account Name could not be set." if is_initial_claim \
			else "Account Name could not be changed.")
		account_name_change_failed.emit(message)
		return false
	if not await load_profile():
		account_name_change_failed.emit(
			"The name changed, but the refreshed profile could not be loaded.")
		return false
	account_name_changed.emit(current_account_name() if current_account_name() != "" else safe_username)
	return true


func account_name_change_available_unix() -> int:
	var timestamp := str(profile.get("username_changed_at", "")).strip_edges()
	if timestamp == "":
		return 0
	var normalized := timestamp.trim_suffix("Z")
	var plus_index := normalized.find("+")
	if plus_index >= 0:
		normalized = normalized.substr(0, plus_index)
	if normalized.contains("."):
		normalized = normalized.get_slice(".", 0)
	return int(Time.get_unix_time_from_datetime_string(normalized)) \
		+ ACCOUNT_RENAME_COOLDOWN_SECONDS


func load_profile() -> bool:
	var response := await _authenticated_request(
		"/rest/v1/profiles?select=id,username,created_at,username_changed_at&limit=1")
	# The Profile screen stays usable before the account-name migration runs.
	if not bool(response.get("ok", false)) and int(response.get("status", 0)) == 400:
		response = await _authenticated_request(
			"/rest/v1/profiles?select=id,username&limit=1")
	if not _response_ok_or_report(response, "profile", "Could not load the profile."):
		return false
	var rows = response.get("data", [])
	profile = rows[0].duplicate(true) if rows is Array and not rows.is_empty() \
		and rows[0] is Dictionary else {}
	if profile.has("username") and current_account_name() == "":
		profile["username"] = ""
	profile_loaded.emit(profile.duplicate(true))
	return true


func load_currency() -> bool:
	var response := await _authenticated_request(
		"/rest/v1/player_currency?select=gun_tokens&limit=1")
	if not _response_ok_or_report(response, "currency", "Could not load Gun Tokens."):
		return false
	var rows = response.get("data", [])
	gun_tokens = int(rows[0].get("gun_tokens", 0)) if rows is Array \
		and not rows.is_empty() and rows[0] is Dictionary else 0
	currency_updated.emit(gun_tokens)
	return true


func load_inventory() -> bool:
	var response := await _authenticated_request(
		"/rest/v1/player_inventory?select=item_id,source,obtained_at&order=obtained_at.desc")
	if not _response_ok_or_report(response, "inventory", "Could not load inventory."):
		return false
	inventory.clear()
	_owned_item_ids.clear()
	var rows = response.get("data", [])
	if rows is Array:
		for value in rows:
			if not value is Dictionary:
				continue
			var item: Dictionary = value.duplicate(true)
			var item_id := SupabaseCosmeticRegistry.sanitize_item_id(
				str(item.get("item_id", "")))
			if item_id == "" or _owned_item_ids.has(item_id):
				continue
			item["item_id"] = item_id
			inventory.append(item)
			_owned_item_ids[item_id] = true
	inventory_updated.emit(inventory.duplicate(true))
	return true


func load_loadout() -> bool:
	var columns := ",".join(SupabaseCosmeticRegistry.LOADOUT_SLOTS)
	var response := await _authenticated_request(
		"/rest/v1/player_loadouts?select=%s&limit=1" % columns)
	var used_legacy_schema := false
	# The character_model entitlement column was added after the progression
	# loadout. During a staggered rollout, retry the otherwise-current schema so
	# hats, outfit pieces, moves, and badges remain available.
	if not bool(response.get("ok", false)) \
			and int(response.get("status", 0)) == 400:
		columns = ",".join(
			SupabaseCosmeticRegistry.PRE_CHARACTER_MODEL_LOADOUT_SLOTS)
		response = await _authenticated_request(
			"/rest/v1/player_loadouts?select=%s&limit=1" % columns)
	# Keep clients usable across the pre-progression seven-slot schema and the
	# original six-slot schema while deployments roll forward.
	if not bool(response.get("ok", false)) \
			and int(response.get("status", 0)) == 400:
		used_legacy_schema = true
		columns = ",".join(SupabaseCosmeticRegistry.PRE_PROGRESSION_LOADOUT_SLOTS)
		response = await _authenticated_request(
			"/rest/v1/player_loadouts?select=%s&limit=1" % columns)
	if not bool(response.get("ok", false)) \
			and int(response.get("status", 0)) == 400:
		columns = ",".join(SupabaseCosmeticRegistry.LEGACY_LOADOUT_SLOTS)
		response = await _authenticated_request(
			"/rest/v1/player_loadouts?select=%s&limit=1" % columns)
	if not _response_ok_or_report(response, "loadout", "Could not load the cosmetic loadout."):
		return false
	var rows = response.get("data", [])
	loadout = SupabaseCosmeticRegistry.sanitize_loadout(
		rows[0] if rows is Array and not rows.is_empty() else {})
	if used_legacy_schema or str(loadout.get("ceremony_theme", "")) == "":
		loadout["ceremony_theme"] = SupabaseCosmeticRegistry.DEFAULT_CEREMONY_THEME_ID
	_apply_local_character_appearance()
	loadout_updated.emit(loadout.duplicate(true))
	return true


func load_shop() -> bool:
	var query := "/rest/v1/shop_items?active=eq.true&shop_visible=eq.true" \
		+ "&select=id,display_name,item_type,description,price,rarity,purchasable," \
		+ "shop_visible,active,category,subcategory,featured,rotation_scope," \
		+ "rotation_starts_at,rotation_ends_at,purchase_count,sort_order,created_at" \
		+ "&order=sort_order.asc,display_name.asc"
	var response: Dictionary
	if is_authenticated():
		response = await _authenticated_request(query)
	else:
		response = await _request(
			query, HTTPClient.METHOD_GET, null, false)
	if not bool(response.get("ok", false)) \
			and int(response.get("status", 0)) == 400:
		query = "/rest/v1/shop_items?active=eq.true&shop_visible=eq.true" \
			+ "&select=id,display_name,item_type,description,price,rarity," \
			+ "purchasable,shop_visible,active,created_at&order=display_name.asc"
		if is_authenticated():
			response = await _authenticated_request(query)
		else:
			response = await _request(query, HTTPClient.METHOD_GET, null, false)
	if not _response_ok_or_report(response, "shop", "Could not load the shop."):
		return false
	shop_items.clear()
	var rows = response.get("data", [])
	if rows is Array:
		for value in rows:
			if not value is Dictionary or not bool(value.get("active", false)) \
					or not bool(value.get("shop_visible", false)):
				continue
			var item: Dictionary = value.duplicate(true)
			var item_id := SupabaseCosmeticRegistry.sanitize_item_id(str(item.get("id", "")))
			if item_id == "":
				continue
			item = Catalog.normalize_item(item)
			shop_items.append(item)
			var slot := SupabaseCosmeticRegistry.item_slot(item)
			if slot != "" and not SupabaseCosmeticRegistry.has_local_visual(item_id, slot):
				print_verbose("SupabaseManager: cosmetic '%s' is data-only; local %s art is pending." \
					% [item_id, slot])
	shop_loaded.emit(shop_items.duplicate(true))
	return true


func purchase_shop_item(item_id: String) -> bool:
	var safe_id := SupabaseCosmeticRegistry.sanitize_item_id(item_id)
	if not is_authenticated():
		purchase_failed.emit(safe_id, "Sign in before buying an item.")
		return false
	if safe_id == "" or _purchase_in_flight.has(safe_id):
		return false
	_purchase_in_flight[safe_id] = true
	var response := await _authenticated_request(
		"/rest/v1/rpc/purchase_shop_item", HTTPClient.METHOD_POST,
		{"p_item_id": safe_id})
	_purchase_in_flight.erase(safe_id)
	if not bool(response.get("ok", false)):
		var message := _response_message(response, "Purchase failed.")
		purchase_failed.emit(safe_id, message)
		backend_error.emit("purchase", message)
		return false
	await load_currency()
	await load_inventory()
	await load_shop()
	purchase_succeeded.emit(safe_id)
	return true


func equip_cosmetic(slot: String, item_id: String) -> bool:
	var safe_slot := SupabaseCosmeticRegistry.sanitize_slot(slot)
	var safe_id := SupabaseCosmeticRegistry.sanitize_item_id(item_id)
	if not is_authenticated():
		equip_failed.emit(safe_slot, safe_id, "Sign in before equipping an item.")
		return false
	if safe_slot == "" or safe_id == "":
		equip_failed.emit(safe_slot, safe_id, "This cosmetic has an invalid slot or item ID.")
		return false
	if not owns_item(safe_id):
		equip_failed.emit(safe_slot, safe_id, "This item is not in the loaded inventory.")
		return false
	var response: Dictionary
	if safe_slot == "ceremony_theme":
		response = await _authenticated_request(
			"/rest/v1/rpc/equip_ceremony_theme", HTTPClient.METHOD_POST,
			{"p_item_id": safe_id})
	else:
		response = await _authenticated_request(
			"/rest/v1/rpc/equip_cosmetic", HTTPClient.METHOD_POST,
			{"p_slot": safe_slot, "p_item_id": safe_id})
	if not bool(response.get("ok", false)):
		var message := _response_message(response, "Equip failed.")
		equip_failed.emit(safe_slot, safe_id, message)
		backend_error.emit("equip", message)
		return false
	if not await load_loadout():
		equip_failed.emit(safe_slot, safe_id,
			"Equipped on the backend, but the refreshed loadout could not be loaded.")
		return false
	equip_succeeded.emit(safe_slot, safe_id)
	return true


func unequip_cosmetic(slot: String) -> bool:
	var safe_slot := SupabaseCosmeticRegistry.sanitize_slot(slot)
	if not is_authenticated():
		unequip_failed.emit(safe_slot, "Sign in before unequipping an item.")
		return false
	if safe_slot == "":
		unequip_failed.emit(safe_slot, "This cosmetic has an invalid loadout slot.")
		return false
	var response := await _authenticated_request(
		"/rest/v1/rpc/unequip_cosmetic", HTTPClient.METHOD_POST,
		{"p_slot": safe_slot})
	if not bool(response.get("ok", false)):
		var message := _response_message(response, "Unequip failed.")
		unequip_failed.emit(safe_slot, message)
		backend_error.emit("unequip", message)
		return false
	if not await load_loadout():
		unequip_failed.emit(safe_slot,
			"Unequipped on the backend, but the refreshed loadout could not be loaded.")
		return false
	unequip_succeeded.emit(safe_slot)
	return true


func reset_cosmetic_loadout() -> bool:
	if not is_authenticated():
		loadout_reset_failed.emit("Sign in before resetting your loadout.")
		return false
	var response := await _authenticated_request(
		"/rest/v1/rpc/reset_cosmetic_loadout", HTTPClient.METHOD_POST, {})
	if not bool(response.get("ok", false)):
		var message := _response_message(response, "Loadout reset failed.")
		loadout_reset_failed.emit(message)
		backend_error.emit("reset_loadout", message)
		return false
	if not await load_loadout():
		loadout_reset_failed.emit(
			"Reset on the backend, but the refreshed loadout could not be loaded.")
		return false
	loadout_reset_succeeded.emit()
	return true


func _restore_session() -> void:
	if not is_configured() or not FileAccess.file_exists(SESSION_PATH):
		# Entitlement-only models must never survive as an unauthenticated local
		# preference. Restore the last public Male/Female selection whenever no
		# account session is available; cloud cosmetics follow the same policy.
		loadout = SupabaseCosmeticRegistry.empty_loadout()
		_apply_local_character_appearance()
		loadout_updated.emit(loadout.duplicate(true))
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if not parsed is Dictionary:
		return
	access_token = str(parsed.get("access_token", ""))
	refresh_token = str(parsed.get("refresh_token", ""))
	authenticated_user_id = str(parsed.get("user_id", ""))
	access_token_expires_at = int(parsed.get("expires_at", 0))
	var saved_claim = parsed.get("username_claim", "")
	_auth_username_claim = "" if saved_claim == null else \
		sanitize_account_name(str(saved_claim))
	if not is_authenticated():
		_clear_runtime_session(false)
		return
	_set_login_state("restoring_session")
	if Time.get_unix_time_from_system() + REFRESH_MARGIN_SECONDS \
			>= access_token_expires_at:
		if not await _refresh_session():
			login_failed.emit(
				"Saved session could not be refreshed. Check the connection or sign in again.")
			return
	login_succeeded.emit(authenticated_user_id)
	await load_all_player_data()
	await _claim_username_from_auth_metadata()


func _authenticated_request(path: String, method := HTTPClient.METHOD_GET,
		payload = null, expected_user_id := "") -> Dictionary:
	if not is_authenticated():
		return {"ok": false, "status": 401, "message": "Not signed in."}
	if not expected_user_id.is_empty() and current_user_id()!=expected_user_id:
		return {"ok":false,"status":409,"message":"Account changed."}
	if not await _ensure_fresh_access_token():
		return {"ok": false, "status": 401, "message": "The session could not be refreshed."}
	if not expected_user_id.is_empty() and current_user_id()!=expected_user_id:
		return {"ok":false,"status":409,"message":"Account changed."}
	var response := await _request(path, method, payload, true)
	if int(response.get("status", 0)) == 401 and await _refresh_session():
		if not expected_user_id.is_empty() and current_user_id()!=expected_user_id:
			return {"ok":false,"status":409,"message":"Account changed."}
		response = await _request(path, method, payload, true)
	return response


func _ensure_fresh_access_token() -> bool:
	if Time.get_unix_time_from_system() + REFRESH_MARGIN_SECONDS \
			< access_token_expires_at:
		return true
	return await _refresh_session()


func _refresh_session() -> bool:
	if _refresh_in_progress:
		var completed = await session_refresh_finished
		return bool(completed[0]) if completed is Array else bool(completed)
	if refresh_token == "" or not is_configured():
		return false
	_refresh_in_progress = true
	var preserved_refresh_token := refresh_token
	var response := await _request(
		"/auth/v1/token?grant_type=refresh_token", HTTPClient.METHOD_POST,
		{"refresh_token": preserved_refresh_token}, false)
	var success := bool(response.get("ok", false)) \
		and _accept_auth_response(response.get("data", {}))
	_refresh_in_progress = false
	if not success:
		# A transient network failure should not erase the only restore token.
		access_token = ""
		refresh_token = preserved_refresh_token
		authenticated_user_id = ""
		access_token_expires_at = 0
		_set_login_state("logged_out")
	session_refresh_finished.emit(success)
	return success


func _request(path: String, method: int, payload, authorized: bool) -> Dictionary:
	if not is_configured():
		return {"ok": false, "status": 0,
			"message": "Supabase is not configured for this build."}
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(request)
	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"apikey: %s" % publishable_key,
	])
	if authorized and access_token != "":
		headers.append("Authorization: Bearer %s" % access_token)
	var body := "" if payload == null else JSON.stringify(payload)
	var start_error := request.request(project_url + path, headers, method, body)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "status": 0,
			"message": "The network request could not be started (error %d)." % start_error}
	var completed = await request.request_completed
	request.queue_free()
	var result := int(completed[0])
	var response_code := int(completed[1])
	var response_body := (completed[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": response_code,
			"message": "Supabase did not respond (network result %d)." % result}
	var data = null
	if response_body != "":
		data = JSON.parse_string(response_body)
	var ok := response_code >= 200 and response_code < 300
	var response := {"ok": ok, "status": response_code, "data": data}
	if not ok:
		response["message"] = _api_error_message(data, response_body, response_code)
	return response


func _accept_auth_response(value) -> bool:
	if not value is Dictionary:
		return false
	var next_access_token := str(value.get("access_token", ""))
	var next_refresh_token := str(value.get("refresh_token", ""))
	var user = value.get("user", {})
	var next_user_id := str(user.get("id", "")) if user is Dictionary else ""
	var user_metadata = user.get("user_metadata", {}) if user is Dictionary else {}
	if user_metadata is Dictionary:
		var metadata_username = user_metadata.get("username", "")
		_auth_username_claim = "" if metadata_username == null else \
			sanitize_account_name(str(metadata_username))
	if next_access_token == "" or next_refresh_token == "" or next_user_id == "":
		return false
	access_token = next_access_token
	refresh_token = next_refresh_token
	authenticated_user_id = next_user_id
	access_token_expires_at = int(value.get("expires_at", 0))
	if access_token_expires_at <= 0:
		access_token_expires_at = int(Time.get_unix_time_from_system()) \
			+ int(value.get("expires_in", 3600))
	_save_session()
	_set_login_state("authenticated")
	return true


func _save_session() -> void:
	var file := FileAccess.open(SESSION_TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SupabaseManager: could not persist the local session.")
		return
	file.store_string(JSON.stringify({
		"schema": 1,
		"access_token": access_token,
		"refresh_token": refresh_token,
		"user_id": authenticated_user_id,
		"expires_at": access_token_expires_at,
		"username_claim": _auth_username_claim,
	}))
	file.close()
	var pending := ProjectSettings.globalize_path(SESSION_TEMP_PATH)
	var target := ProjectSettings.globalize_path(SESSION_PATH)
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(pending, target) != OK:
		push_warning("SupabaseManager: could not finalize the local session file.")


func _clear_runtime_session(remove_saved: bool) -> void:
	access_token = ""
	refresh_token = ""
	authenticated_user_id = ""
	access_token_expires_at = 0
	_auth_username_claim = ""
	profile.clear()
	gun_tokens = 0
	inventory.clear()
	loadout = SupabaseCosmeticRegistry.empty_loadout()
	_owned_item_ids.clear()
	_set_login_state("logged_out")
	if remove_saved and FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	profile_loaded.emit({})
	currency_updated.emit(0)
	inventory_updated.emit([])
	shop_loaded.emit(shop_items.duplicate(true))
	_apply_local_character_appearance()
	loadout_updated.emit(loadout.duplicate(true))


func _claim_username_from_auth_metadata() -> bool:
	if not is_authenticated() or _auth_username_claim == "":
		return false
	if current_account_name() != "":
		_auth_username_claim = ""
		_save_session()
		return true
	var response := await _authenticated_request(
		"/rest/v1/rpc/claim_profile_username", HTTPClient.METHOD_POST,
		{"p_username": _auth_username_claim})
	if not bool(response.get("ok", false)):
		# Keep the claim in the session so a temporary migration/network gap can
		# be retried on the next authenticated launch.
		return false
	_auth_username_claim = ""
	_save_session()
	return await load_profile()


func _apply_local_character_appearance() -> void:
	var model_id := SupabaseCosmeticRegistry.local_character_model_id(
		str(loadout.get("character_model", "")))
	var next_preferences := PlayerPrefs.snapshot()
	var current_model := PlayerSkinRegistry.sanitize_model_id(str(
		next_preferences.get("character_model_id", PlayerSkinRegistry.DEFAULT_MODEL_ID)))
	if PlayerSkinRegistry.is_public_model_id(current_model):
		next_preferences["character_base_model_id"] = current_model
	var base_model := PlayerSkinRegistry.sanitize_public_model_id(str(
		next_preferences.get("character_base_model_id",
			PlayerSkinRegistry.DEFAULT_MODEL_ID)))
	var resolved_model := model_id if model_id != "" else base_model
	var skin_id := SupabaseCosmeticRegistry.local_character_skin_id(
		str(loadout.get("character_skin", "")))
	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.has_method("set_local_appearance"):
		network_manager.call("set_local_appearance",
			skin_id if skin_id != "" else str(next_preferences.get(
				"character_skin_id", PlayerSkinRegistry.DEFAULT_SKIN_ID)),
			resolved_model)
		return
	if skin_id != "":
		next_preferences["character_skin_id"] = skin_id
	next_preferences["character_model_id"] = resolved_model
	PlayerPrefs.apply_transaction(next_preferences)


func _looks_like_email(value: String) -> bool:
	var cleaned := value.strip_edges()
	if cleaned.contains(" "):
		return false
	var at_index := cleaned.find("@")
	var dot_index := cleaned.find(".", at_index + 2)
	return at_index > 0 and dot_index > at_index + 1 \
		and dot_index < cleaned.length() - 1


func _can_start_auth(email: String, password: String) -> bool:
	if not is_configured():
		login_failed.emit("Supabase is not configured for this build.")
		return false
	if login_state in ["authenticating", "restoring_session"]:
		return false
	if not _looks_like_email(email):
		login_failed.emit("Enter a valid email address.")
		return false
	if password.length() < 6:
		login_failed.emit("Password must be at least 6 characters.")
		return false
	return true


func _response_ok_or_report(response: Dictionary, operation: String,
		fallback: String) -> bool:
	if bool(response.get("ok", false)):
		return true
	backend_error.emit(operation, _response_message(response, fallback))
	return false


func _response_message(response: Dictionary, fallback: String) -> String:
	var message := str(response.get("message", "")).strip_edges()
	return message if message != "" else fallback


func _api_error_message(data, raw_body: String, status: int) -> String:
	if data is Dictionary:
		for key in ["message", "msg", "error_description", "error", "details", "hint"]:
			var value := str(data.get(key, "")).strip_edges()
			if value != "":
				return value
	if raw_body.strip_edges() != "":
		return raw_body.strip_edges().substr(0, 240)
	return "Supabase request failed (HTTP %d)." % status


func _set_login_state(value: String) -> void:
	if login_state == value:
		return
	login_state = value
	login_state_changed.emit(login_state)


func _load_configuration() -> void:
	var url_override := OS.get_environment("ONEGUN_SUPABASE_URL").strip_edges()
	var key_override := OS.get_environment(
		"ONEGUN_SUPABASE_PUBLISHABLE_KEY").strip_edges()
	var config := {}
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			config = parsed
	if url_override != "":
		project_url = url_override.trim_suffix("/")
	else:
		project_url = str(config.get("project_url", "")).strip_edges().trim_suffix("/")
	if key_override != "":
		publishable_key = key_override
	else:
		publishable_key = str(config.get("publishable_key", "")).strip_edges()
	if not bool(config.get("enabled", true)) and url_override == "" and key_override == "":
		project_url = ""
		publishable_key = ""
	var message := _configuration_error()
	if message != "":
		project_url = ""
		publishable_key = ""
		push_warning("SupabaseManager: %s" % message)
	configuration_loaded.emit(is_configured(), message)


func _is_forbidden_credential(value: String) -> bool:
	var lower_key := value.to_lower()
	if lower_key.begins_with("sb_secret_") or lower_key.contains("service_role"):
		return true
	var segments := value.split(".")
	if segments.size() != 3:
		return false
	var payload := str(segments[1]).replace("-", "+").replace("_", "/")
	while payload.length() % 4 != 0:
		payload += "="
	var decoded := Marshalls.base64_to_raw(payload)
	if decoded.is_empty():
		return false
	var parsed = JSON.parse_string(decoded.get_string_from_utf8())
	return parsed is Dictionary \
		and str(parsed.get("role", "")).to_lower() == "service_role"


func _configuration_error() -> String:
	if project_url == "" or publishable_key == "":
		return "Supabase URL or publishable key is missing."
	if not project_url.begins_with("https://") or project_url.contains(" "):
		return "Supabase project URL must be HTTPS."
	if _is_forbidden_credential(publishable_key):
		return "A secret/service-role key was rejected; use only a publishable/anon key."
	return ""
