extends Node

@warning_ignore("unused_signal")
signal player_eliminated(victim_name, killer_name, weapon_icon)

@warning_ignore("unused_signal")
signal player_disarmed(victim_name, disarmer_name, weapon_icon)

@warning_ignore("unused_signal")
signal gun_picked_up(player_name: String)

@warning_ignore("unused_signal")
signal gun_dropped()

@warning_ignore("unused_signal")
signal hud_notification(message: String)

@warning_ignore("unused_signal")
signal melee_hit_landed(hitter_name: String)
