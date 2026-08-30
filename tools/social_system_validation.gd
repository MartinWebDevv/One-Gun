extends SceneTree

var _failures := 0


class FakeSocialBackend extends Node:
	var response_data: Dictionary

	func is_authenticated() -> bool:
		return true

	func _authenticated_request(_path: String, _method: int,
			_payload = null) -> Dictionary:
		return {"ok": true, "status": 200, "data": response_data.duplicate(true)}

	func _response_message(response: Dictionary, fallback: String) -> String:
		return str(response.get("message", fallback))


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)


func _run() -> void:
	await process_frame
	var social_script = load("res://supabase/social_manager.gd")
	var overlay_script = load("res://UI/social_overlay.gd")
	var lobby_hub_script = load("res://UI/lobby_player_hub_overlay.gd")
	var friends_orb_script = load("res://UI/components/friends_quick_access_orb.gd")
	var invite_toast_script = load("res://UI/components/lobby_invite_notification.gd")
	_check(social_script != null and overlay_script != null
			and lobby_hub_script != null and friends_orb_script != null
			and invite_toast_script != null,
		"social manager, Friends overlay/orb/toast, and lobby Player Hub resources load")
	_check(social_script.is_valid_join_endpoint("100.64.0.1", 24545)
			and social_script.is_valid_join_endpoint("100.127.255.254", 65535)
			and social_script.is_valid_join_endpoint("127.0.0.1", 24545)
			and not social_script.is_valid_join_endpoint("100.128.0.1", 24545)
			and not social_script.is_valid_join_endpoint("192.168.1.2", 24545)
			and not social_script.is_valid_join_endpoint("100.64.0.1", 0),
		"friend joins accept only valid Tailscale/localhost UDP endpoints")
	var normalized: Dictionary = social_script.normalized_snapshot({
		"friends": [{"user_id": "friend"}],
		"incoming_requests": "invalid",
		"invites": [null, {"id": "invite"}],
	})
	_check(normalized["friends"].size() == 1
			and normalized["incoming_requests"].is_empty()
			and normalized["invites"].size() == 1,
		"malformed backend collections are normalized without exposing invalid rows")

	var fixture := {
		"friends": [{
			"user_id": "40000000-0000-0000-0000-000000000002",
			"username": "OnlineFriend", "online": true, "activity": "lobby",
			"lobby_name": "Friend Lobby", "lobby_address": "100.64.2.3",
			"lobby_port": 24545, "joinable": true,
		}],
		"incoming_requests": [{
			"user_id": "40000000-0000-0000-0000-000000000003",
			"username": "IncomingFriend",
		}],
		"outgoing_requests": [{
			"user_id": "40000000-0000-0000-0000-000000000004",
			"username": "PendingFriend",
		}],
		"invites": [{
			"id": "50000000-0000-0000-0000-000000000001",
			"sender_id": "40000000-0000-0000-0000-000000000002",
			"username": "OnlineFriend", "lobby_name": "Friend Lobby",
			"lobby_address": "100.64.2.3", "lobby_port": 24545,
		}],
		"server_time": "2026-08-26T12:00:00Z",
	}
	var manager = root.get_node("SocialManager")
	var real_backend = manager.get("_backend")
	var fake_backend := FakeSocialBackend.new()
	fake_backend.response_data = fixture
	root.add_child(fake_backend)
	manager.set("_backend", fake_backend)
	manager.set("snapshot", fixture.duplicate(true))
	manager.set("_refreshing", true)

	var overlay = overlay_script.new()
	root.add_child(overlay)
	await process_frame
	await process_frame
	_check(overlay.find_child("FriendsCabinet", true, false) != null,
		"Friends overlay builds its full-screen cabinet")
	var online_label := overlay.get("_online_label") as Label
	_check(online_label != null and online_label.text == "1 ONLINE",
		"Friends overlay reports online friends from the private snapshot")
	_check(overlay.find_child("JoinFriendButton", true, false) != null,
		"joinable friend presence exposes a Join action")
	_check(overlay.find_child("AcceptFriendButton", true, false) != null
			and overlay.find_child("DenyFriendButton", true, false) != null,
		"incoming requests expose Accept and Deny actions")
	_check(overlay.find_child("AcceptLobbyInviteButton", true, false) != null
			and overlay.find_child("DenyLobbyInviteButton", true, false) != null,
		"lobby invitations expose Accept & Join and Deny actions")

	var hub = lobby_hub_script.new()
	root.add_child(hub)
	var friends_orb = friends_orb_script.new()
	root.add_child(friends_orb)
	var invite_toast = invite_toast_script.new()
	root.add_child(invite_toast)
	await process_frame
	_check(hub.find_child("OpenLockerButton", true, false) != null
			and hub.find_child("OpenPrizeCounterButton", true, false) != null
			and hub.find_child("OpenProgressionButton", true, false) != null
			and hub.find_child("OpenFriendsButton", true, false) == null,
		"online Player Hub preserves its three destinations without duplicating Friends")
	_check(friends_orb.find_child("BlueMaleMascotPortrait", true, false) != null
			and friends_orb.find_child("FriendsHoverLabel", true, false) != null,
		"separate Friends orb contains the blue mascot portrait and hover label")
	_check(invite_toast.find_child("AcceptLobbyInviteToastButton", true, false) != null
			and invite_toast.find_child("DeclineLobbyInviteToastButton", true, false) != null,
		"separate invitation toast exposes Accept and Deny controls")

	overlay.queue_free()
	hub.queue_free()
	friends_orb.queue_free()
	invite_toast.queue_free()
	manager.set("_refreshing", false)
	manager.set("_backend", real_backend)
	manager.set("snapshot", social_script.normalized_snapshot({}))
	fake_backend.queue_free()
	await process_frame
	if _failures == 0:
		print("SOCIAL SYSTEM VALIDATION: PASS")
		quit(0)
	else:
		push_error("SOCIAL SYSTEM VALIDATION FAILED: %d issue(s)" % _failures)
		quit(1)
