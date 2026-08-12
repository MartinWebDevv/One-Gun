class_name OneGunBuildInfo
extends RefCounted

# Player-facing releases and network compatibility are intentionally separate.
# A transport (ENet/Tailscale today, Steam later) only needs to exchange this
# neutral payload before a connection is admitted to the gameplay roster.
const GAME_VERSION := "0.0.4"
const NETWORK_PROTOCOL := 1
const RELEASE_NOTES_PATH := "res://release_notes.json"


static func compatibility_payload() -> Dictionary:
	return {
		"game_version": GAME_VERSION,
		"protocol": NETWORK_PROTOCOL,
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
	return "v%s | Protocol %d" % [GAME_VERSION, NETWORK_PROTOCOL] if OS.is_debug_build() else "v%s" % GAME_VERSION


static func load_latest_release() -> Dictionary:
	if not FileAccess.file_exists(RELEASE_NOTES_PATH):
		return {"version": GAME_VERSION, "categories": {}}
	var file := FileAccess.open(RELEASE_NOTES_PATH, FileAccess.READ)
	if file == null:
		return {"version": GAME_VERSION, "categories": {}}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {"version": GAME_VERSION, "categories": {}}
