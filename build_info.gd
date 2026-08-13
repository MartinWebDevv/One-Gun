class_name OneGunBuildInfo
extends RefCounted

# Player-facing releases and network compatibility are intentionally separate.
# A transport (ENet/Tailscale today, Steam later) only needs to exchange this
# neutral payload before a connection is admitted to the gameplay roster.
const GAME_VERSION := "0.0.4"
const NETWORK_PROTOCOL := 1
const DEFAULT_BUILD_ID := "dev"
const BUILD_METADATA_PATH := "res://build_metadata.json"
const RELEASE_NOTES_PATH := "res://release_notes.json"

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
	var remote_version := str(remote.get("game_version", "unknown"))
	var remote_protocol := int(remote.get("protocol", -1))
	if remote_version != GAME_VERSION:
		return "Incompatible game version. Host: v%s | Yours: v%s" % [remote_version, GAME_VERSION]
	if remote_protocol != NETWORK_PROTOCOL:
		return "Incompatible network protocol. Host: %d | Yours: %d" % [remote_protocol, NETWORK_PROTOCOL]
	return ""


static func host_compatibility_error(client: Dictionary) -> String:
	var client_version := str(client.get("game_version", "unknown"))
	var client_protocol := int(client.get("protocol", -1))
	if client_version != GAME_VERSION:
		return "Incompatible game version. Host: v%s | Yours: v%s" % [GAME_VERSION, client_version]
	if client_protocol != NETWORK_PROTOCOL:
		return "Incompatible network protocol. Host: %d | Yours: %d" % [NETWORK_PROTOCOL, client_protocol]
	return ""


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
