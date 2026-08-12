extends Node

@warning_ignore("unused_signal")
signal player_eliminated(victim_name, killer_name, weapon_icon)
signal actor_eliminated(victim_actor_id: int, killer_actor_id: int, weapon_icon: String)

@warning_ignore("unused_signal")
signal player_disarmed(victim_name, disarmer_name, weapon_icon)
signal actor_disarmed(victim_actor_id: int, disarmer_actor_id: int, weapon_icon: String)

@warning_ignore("unused_signal")
signal gun_picked_up(player_name: String)
signal actor_gun_picked_up(actor_id: int)

@warning_ignore("unused_signal")
signal gun_dropped()

@warning_ignore("unused_signal")
signal hud_notification(message: String)

@warning_ignore("unused_signal")
signal melee_hit_landed(hitter_name: String)
signal actor_melee_hit_landed(actor_id: int)

# Typed, validated combat presentation event. event_kind is one of
# gun_hit/gun_elimination/melee_hit/melee_elimination/hazard_*.
@warning_ignore("unused_signal")
signal combat_feedback(attacker_name: String, event_kind: String)
signal actor_combat_feedback(attacker_actor_id: int, event_kind: String)

# Approximate perception cue for bots. Silent Steps suppresses only footstep
# emissions; weapon/item noise remains intentionally audible.
signal combat_noise(world_position: Vector3, source_actor_id: int, kind: String, loudness: float)

# Marker supply requests stay on the shared event bus so held/reparented
# pickup objects do not retain a direct dependency on the local RoundManager.
signal melee_marker_refill_requested(melee)
signal item_marker_refill_requested(item)
