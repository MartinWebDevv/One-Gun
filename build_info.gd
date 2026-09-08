class_name OneGunBuildInfo
extends RefCounted

# Player-facing releases and network compatibility are intentionally separate.
# A transport (ENet/Tailscale today, Steam later) only needs to exchange this
# neutral payload before a connection is admitted to the gameplay roster.
const GAME_VERSION := "0.0.7"
const NETWORK_PROTOCOL := 4
const DEFAULT_BUILD_ID := "dev"
const REJECTION_GAME_VERSION := "game_version"
const REJECTION_NETWORK_PROTOCOL := "network_protocol"
const BUILD_METADATA_PATH := "res://build_metadata.json"
const RELEASE_NOTES_PATH := "res://release_notes.json"
const RELEASE_POPUP_STATE_PATH := "user://release_popup_state.cfg"
const RELEASE_POPUP_STATE_SECTION := "release_notes"
const RELEASE_POPUP_STATE_KEY := "last_seen_popup_id"


static var _metadata_loaded := false
static var _metadata: Dictionary = {}


static func build_id() -> String:
	_load_build_metadata()
	return _sanitize_build_id(str(_metadata.get("build_id", DEFAULT_BUILD_ID)))


static func commit_sha() -> String:
	_load_build_metadata()
	return str(_metadata.get("commit_sha", "")).strip_edges()


static func summary() -> String:
	return "One Gun %s | build %s | protocol %d" % [
		GAME_VERSION, build_id(), NETWORK_PROTOCOL]


static func compatibility_payload() -> Dictionary:
	return {
		"game_version": GAME_VERSION,
		"protocol": NETWORK_PROTOCOL,
		"build_id": build_id(),
	}


static func compatibility_error(remote: Dictionary) -> String:
	return str(compatibility_rejection(remote).get("detail", ""))


static func compatibility_rejection(remote: Dictionary) -> Dictionary:
	var remote_version := str(remote.get("game_version", "unknown"))
	var remote_protocol := int(remote.get("protocol", -1))
	if remote_version != GAME_VERSION:
		return {
			"reason": REJECTION_GAME_VERSION,
			"detail": "Incompatible game version. Host: v%s | Yours: v%s" % [remote_version, GAME_VERSION],
		}
	if remote_protocol != NETWORK_PROTOCOL:
		return {
			"reason": REJECTION_NETWORK_PROTOCOL,
			"detail": "Incompatible network protocol. Host: %d | Yours: %d" % [remote_protocol, NETWORK_PROTOCOL],
		}
	return {}


static func host_compatibility_error(client: Dictionary) -> String:
	return str(host_compatibility_rejection(client).get("detail", ""))


static func host_compatibility_rejection(client: Dictionary) -> Dictionary:
	var client_version := str(client.get("game_version", "unknown"))
	var client_protocol := int(client.get("protocol", -1))
	if client_version != GAME_VERSION:
		return {
			"reason": REJECTION_GAME_VERSION,
			"detail": "Incompatible game version. Host: v%s | Yours: v%s" % [GAME_VERSION, client_version],
		}
	if client_protocol != NETWORK_PROTOCOL:
		return {
			"reason": REJECTION_NETWORK_PROTOCOL,
			"detail": "Incompatible network protocol. Host: %d | Yours: %d" % [NETWORK_PROTOCOL, client_protocol],
		}
	return {}


static func is_version_rejection(reason: String) -> bool:
	return reason in [REJECTION_GAME_VERSION, REJECTION_NETWORK_PROTOCOL]


static func version_mismatch_message(detail := "") -> String:
	var message := "Your copy of One Gun does not match the server.\n\nRestart the game to download the newest update."
	var cleaned_detail := str(detail).strip_edges()
	return "%s\n\n%s" % [message, cleaned_detail] if cleaned_detail != "" else message


static func footer_text() -> String:
	var text := "v%s | %s" % [GAME_VERSION, build_id()]
	return "%s | Protocol %d" % [text, NETWORK_PROTOCOL] if OS.is_debug_build() else text


static func payload_build_id(payload: Dictionary) -> String:
	var value := str(payload.get("build_id", "unknown")).strip_edges()
	return value.substr(0, 64) if value != "" else "unknown"


static func _load_build_metadata() -> void:
	if _metadata_loaded:
		return
	_metadata_loaded = true
	if not FileAccess.file_exists(BUILD_METADATA_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BUILD_METADATA_PATH))
	if parsed is Dictionary:
		_metadata = parsed
	else:
		push_warning("Build metadata is invalid JSON; using build '%s'." % DEFAULT_BUILD_ID)


static func _sanitize_build_id(value: String) -> String:
	var cleaned := value.strip_edges()
	var validator := RegEx.new()
	if validator.compile("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") != OK \
			or validator.search(cleaned) == null:
		return DEFAULT_BUILD_ID
	return cleaned


static func load_latest_release() -> Dictionary:
	if not FileAccess.file_exists(RELEASE_NOTES_PATH):
		return {"version": GAME_VERSION, "categories": {}}
	var file := FileAccess.open(RELEASE_NOTES_PATH, FileAccess.READ)
	if file == null:
		return {"version": GAME_VERSION, "categories": {}}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {"version": GAME_VERSION, "categories": {}}

static func release_popup_id(release: Dictionary) -> String:
	var explicit_id := str(release.get("popup_id", "")).strip_edges()
	if explicit_id != "":
		return explicit_id.substr(0, 128)
	return str(release.get("version", GAME_VERSION)).strip_edges().substr(0, 128)


static func should_show_release_popup(release: Dictionary) -> bool:
	if not bool(release.get("show_on_launch", false)):
		return false
	var popup_id := release_popup_id(release)
	if popup_id == "":
		return false
	var state := ConfigFile.new()
	if state.load(RELEASE_POPUP_STATE_PATH) != OK:
		return true
	return str(state.get_value(
			RELEASE_POPUP_STATE_SECTION, RELEASE_POPUP_STATE_KEY, "")) != popup_id


static func mark_release_popup_seen(release: Dictionary) -> void:
	var popup_id := release_popup_id(release)
	if popup_id == "":
		return
	var state := ConfigFile.new()
	state.load(RELEASE_POPUP_STATE_PATH)
	state.set_value(RELEASE_POPUP_STATE_SECTION, RELEASE_POPUP_STATE_KEY, popup_id)
	var error := state.save(RELEASE_POPUP_STATE_PATH)
	if error != OK:
		push_warning("Could not save release-popup state: %s" % error_string(error))
