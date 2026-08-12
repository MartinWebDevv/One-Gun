extends Resource
class_name WeaponData

# ============================================================
# WeaponData — data-driven definition for a melee weapon type.
#
# One .tres file per weapon (Sword, Bat, Stick, Crowbar, FryingPan).
# melee_weapon.gd reads from this at spawn time via apply_weapon_data().
# Tiers modify stats at runtime — the base resource is never mutated.
# ============================================================

@export var weapon_name: String = "Unnamed"

# Scene path to the 3D model used as a visual child.
@export_file("*.tscn", "*.glb") var model_scene_path: String = ""
# Longest raw mesh dimension before held_scale. The registry normalizes this
# measurement so every weapon presents at the same held length.
@export var raw_model_length: float = 1.0

# -- Handling feel --
# reach_multiplier scales the HitBox CollisionShape radius at spawn time.
# 1.0 = base size as defined in melee_weapon.tscn.
@export var reach_multiplier: float = 1.0

# Model-local point placed at the paw, plus the model's held orientation/scale.
# Explicit grip anchors compensate for the five assets' different origins.
@export var held_grip_anchor: Vector3 = Vector3.ZERO
@export var held_rotation: Vector3 = Vector3(-PI/2, PI, 0)
@export var held_scale: float = 1.0

# -- Base timing (seconds) at Tier 1 --
@export var base_windup_time: float = 0.1
@export var base_active_time: float = 0.2
@export var base_recovery_time: float = 0.3

# -- Stamina cost at Tier 1 --
@export var base_stamina_cost: float = 15.0

@export_multiline var description: String = ""
