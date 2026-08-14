class_name OneGunMatchServerContext
extends RefCounted

# Edgegap Matchmaker injects these values into dynamically assigned game
# servers. This parser deliberately keeps the raw ticket payload server-only.
const MATCH_ID_VARIABLE := "MM_MATCH_ID"
const TICKET_IDS_VARIABLE := "MM_TICKET_IDS"
const TICKET_VARIABLE_PREFIX := "MM_TICKET_"
const OPTIONAL_JSON_VARIABLES := [
	"MM_GROUPS",
	"MM_TEAMS",
	"MM_INTERSECTION",
	"MM_EQUALITY",
]


static func from_environment() -> Dictionary:
	var values := {
		MATCH_ID_VARIABLE: OS.get_environment(MATCH_ID_VARIABLE),
		TICKET_IDS_VARIABLE: OS.get_environment(TICKET_IDS_VARIABLE),
		"MM_MATCH_PROFILE": OS.get_environment("MM_MATCH_PROFILE"),
		"MM_EXPANSION_STAGE": OS.get_environment("MM_EXPANSION_STAGE"),
	}
	for key in OPTIONAL_JSON_VARIABLES:
		values[key] = OS.get_environment(key)
	var raw_ticket_ids := str(values[TICKET_IDS_VARIABLE]).strip_edges()
	var parsed_ids = JSON.parse_string(raw_ticket_ids) if raw_ticket_ids != "" else null
	if parsed_ids is Array:
		for ticket_value in parsed_ids:
			var ticket_id := str(ticket_value).strip_edges()
			if ticket_id != "":
				values[TICKET_VARIABLE_PREFIX + ticket_id] = OS.get_environment(
					TICKET_VARIABLE_PREFIX + ticket_id)
	return from_values(values)


static func from_values(values: Dictionary) -> Dictionary:
	var match_id := str(values.get(MATCH_ID_VARIABLE, "")).strip_edges()
	var raw_ticket_ids := str(values.get(TICKET_IDS_VARIABLE, "")).strip_edges()
	var active := match_id != "" or raw_ticket_ids != ""
	if not active:
		return {
			"active": false,
			"valid": true,
			"errors": [],
			"match_id": "",
			"ticket_ids": [],
			"tickets": {},
		}

	var errors: Array[String] = []
	var ticket_ids: Array[String] = []
	var tickets: Dictionary = {}
	if match_id == "":
		errors.append("MM_MATCH_ID is missing.")
	var parsed_ids = JSON.parse_string(raw_ticket_ids)
	if not parsed_ids is Array:
		errors.append("MM_TICKET_IDS must be a JSON array.")
	else:
		for ticket_value in parsed_ids:
			var ticket_id := str(ticket_value).strip_edges()
			if not _is_safe_ticket_id(ticket_id):
				errors.append("MM_TICKET_IDS contains an invalid ticket identifier.")
				continue
			if ticket_ids.has(ticket_id):
				errors.append("MM_TICKET_IDS contains a duplicate ticket identifier.")
				continue
			ticket_ids.append(ticket_id)
			var variable_name := TICKET_VARIABLE_PREFIX + ticket_id
			var raw_ticket := str(values.get(variable_name, "")).strip_edges()
			if raw_ticket == "":
				errors.append("%s is missing." % variable_name)
				continue
			var parsed_ticket = JSON.parse_string(raw_ticket)
			if not parsed_ticket is Dictionary:
				errors.append("%s must contain a JSON object." % variable_name)
				continue
			if str(parsed_ticket.get("id", "")) != ticket_id:
				errors.append("%s does not match its embedded ticket ID." % variable_name)
				continue
			tickets[ticket_id] = parsed_ticket
	if ticket_ids.is_empty():
		errors.append("MM_TICKET_IDS contains no assigned players.")

	var optional_data: Dictionary = {}
	for key in OPTIONAL_JSON_VARIABLES:
		var raw_value := str(values.get(key, "")).strip_edges()
		if raw_value == "":
			continue
		var parsed_value = JSON.parse_string(raw_value)
		if not parsed_value is Dictionary:
			errors.append("%s must contain a JSON object." % key)
		else:
			optional_data[key] = parsed_value

	return {
		"active": true,
		"valid": errors.is_empty(),
		"errors": errors,
		"match_id": match_id.substr(0, 160),
		"profile": str(values.get("MM_MATCH_PROFILE", "")).strip_edges().substr(0, 64),
		"expansion_stage": str(values.get("MM_EXPANSION_STAGE", "")).strip_edges().substr(0, 64),
		"ticket_ids": ticket_ids,
		"tickets": tickets,
		"groups": optional_data.get("MM_GROUPS", {}),
		"teams": optional_data.get("MM_TEAMS", {}),
		"intersection": optional_data.get("MM_INTERSECTION", {}),
		"equality": optional_data.get("MM_EQUALITY", {}),
	}


static func _is_safe_ticket_id(ticket_id: String) -> bool:
	if ticket_id.is_empty() or ticket_id.length() > 128:
		return false
	for character in ticket_id:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true