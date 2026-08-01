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

# Typed, validated combat presentation event. event_kind is one of
# gun_hit/gun_elimination/melee_hit/melee_elimination/hazard_*.
@warning_ignore("unused_signal")
signal combat_feedback(attacker_name: String, event_kind: String)
