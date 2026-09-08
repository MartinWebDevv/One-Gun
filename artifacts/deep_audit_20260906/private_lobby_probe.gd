extends Node

func _ready() -> void:
    _run.call_deferred()

func _run() -> void:
    var host := "--host" in OS.get_cmdline_user_args()
    var ok: bool
    if host:
        ok = NetworkManager.host_game(24903, "Audit private admission", {"privacy": "private", "max_players": 2, "share_code": "AUDITCODE"})
    else:
        ok = NetworkManager.join_game("127.0.0.1", 24903)
    if not ok:
        push_error("AUDIT_PRIVATE start failed")
        get_tree().quit(1)
        return
    var deadline := Time.get_ticks_msec() + 15000
    while NetworkManager.peers.size() < 2 and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
    print("AUDIT_PRIVATE role=%s peers=%d private=%s client_supplied_no_code=true" % ["host" if host else "client", NetworkManager.peers.size(), NetworkManager.lobby_privacy])
    var admitted := NetworkManager.peers.size() == 2
    await get_tree().create_timer(1.0 if host else 0.5).timeout
    NetworkManager.disconnect_net()
    await get_tree().create_timer(0.2).timeout
    get_tree().quit(0 if admitted else 1)
