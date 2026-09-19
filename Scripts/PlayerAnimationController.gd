extends Node
class_name PlayerAnimationController

# ============================================================
# REFERENCES
# ============================================================
@export var player: Player
@export var character_model: Node3D

var animation_tree: AnimationTree
var animation_player: AnimationPlayer
var anim_playback: AnimationNodeStateMachinePlayback

# ============================================================
# CHARACTER MESHES (shader params get pushed to all of these)
# ============================================================
var mesh_instances: Array[MeshInstance3D] = []

# ============================================================
# FOOT IK
# ============================================================
@export_group("Foot IK")
@export var skeleton: Skeleton3D
@export var left_foot_bone: String = "LeftFoot"
@export var right_foot_bone: String = "RightFoot"
@export var left_target: Node3D
@export var right_target: Node3D
@export var foot_contact_threshold: float = 0.05
@export var ik_blend_speed: float = 12.0
@export var sole_offset: float = 0.03

var left_bone_idx: int = -1
var right_bone_idx: int = -1
var left_weight: float = 0.0
var right_weight: float = 0.0

# ============================================================
# LOCOMOTION BLEND
# Blends on the character's ACTUAL planar speed rather than the
# predicted (look-ahead) speed. Prediction runs ahead of reality by
# design, so the legs were cycling at a speed the body hadn't reached
# yet -- which is exactly what makes footfalls look like they're
# skating. Lightly smoothed, since raw per-frame speed can jitter
# slightly on collisions and slopes.
# ============================================================
@export_group("Locomotion Blend")
@export var speed_blend_smoothing_time: float = 0.06

var smoothed_locomotion_speed: float = 0.0

# ============================================================
# LANDING ANTICIPATION
# Predicts touchdown before it happens (raycast + kinematic
# time-to-impact) and starts the Land animation early enough that it
# FINISHES right around actual impact, instead of starting at impact
# and leaving the legs planted in a landing pose for land_anim_duration
# while the body keeps moving. Falls back to the old reactive trigger
# for falls too short to have given enough warning.
# ============================================================
@export_group("Landing Anticipation")
## How long the Land animation takes to play. Also the anticipation
## lead time -- landing is predicted this far ahead of actual impact.
@export var land_anim_duration: float = 0.25
## Max distance to check for ground when predicting a landing.
@export var landing_predict_ray_length: float = 50.0
## Distance from player.global_position down to where the feet
## actually touch the ground, along gravity_direction. The raycast
## measures from the character's origin (often a capsule's center),
## not its feet, so without this the predicted distance -- and
## therefore the predicted time-to-land -- is too large, firing the
## animation too early. If landing anticipates too early, increase
## this (roughly toward your collision shape's half-height); if it's
## now firing too late/not enough warning, decrease it.
@export var ground_contact_offset: float = 0.0

var land_anim_active: bool = false
var landing_timer: float = 0.0

# ============================================================
# STATE
# ============================================================
enum AnimState {
	IDLE,
	JOG,
	RUN,
	JUMP,
	DOUBLE_JUMP,
	TRIPLE_JUMP,
	FALL,
	LAND
}

const LOCOMOTION_BLEND_PARAM := "parameters/BlendSpace1D/blend_position"

var current_anim_state := AnimState.IDLE
var was_on_floor := true


func _ready() -> void:
	if not player:
		push_error("PlayerAnimationController: 'player' not assigned")
		return
	if not character_model:
		push_error("PlayerAnimationController: 'character_model' not assigned")
		return

	animation_player = _find_first_of_type(character_model, "AnimationPlayer") as AnimationPlayer
	animation_tree = _find_first_of_type(player, "AnimationTree") as AnimationTree

	if not animation_player:
		push_error("PlayerAnimationController: no AnimationPlayer found anywhere under %s" % character_model.name)
	if not animation_tree:
		push_error("PlayerAnimationController: no AnimationTree found anywhere under %s" % player.name)
		return

	animation_tree.active = true
	anim_playback = animation_tree.get("parameters/playback")

	if not anim_playback:
		push_error("PlayerAnimationController: 'parameters/playback' came back null -- Tree Root probably isn't an AnimationNodeStateMachine")

	mesh_instances.clear()
	_find_all_of_type(character_model, "MeshInstance3D", mesh_instances)
	if mesh_instances.is_empty():
		push_error("PlayerAnimationController: no MeshInstance3D found under %s -- lean/squash shader params won't apply" % character_model.name)

	if skeleton:
		left_bone_idx = skeleton.find_bone(left_foot_bone)
		right_bone_idx = skeleton.find_bone(right_foot_bone)
		if left_bone_idx == -1:
			push_error("PlayerAnimationController: bone '%s' not found on skeleton" % left_foot_bone)
		if right_bone_idx == -1:
			push_error("PlayerAnimationController: bone '%s' not found on skeleton" % right_foot_bone)
	else:
		push_error("PlayerAnimationController: 'skeleton' not assigned -- foot IK disabled")


func _find_first_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found := _find_first_of_type(child, type_name)
		if found:
			return found
	return null


func _find_all_of_type(root: Node, type_name: String, out_list: Array) -> void:
	for child in root.get_children():
		if child.is_class(type_name):
			out_list.append(child)
		_find_all_of_type(child, type_name, out_list)


func _debug_print_tree(root: Node, indent: String = "") -> void:
	print(indent, root.name, "  [", root.get_class(), "]")
	for child in root.get_children():
		_debug_print_tree(child, indent + "  ")


## Casts a ray toward the ground (along current gravity_direction) and
## returns true if, based on current fall speed and gravity's
## acceleration, we're on track to touch down within `lead_time`
## seconds. Re-evaluated every frame while airborne, so the estimate
## keeps self-correcting as the player gets closer to the ground.
func _predict_landing_within(lead_time: float) -> bool:
	if not player or not player.gravity_controller:
		return false

	var gc: GravityController = player.gravity_controller
	var gravity_dir: Vector3 = gc.gravity_direction

	var fall_speed: float = player.velocity.dot(gravity_dir)
	if fall_speed <= 0.0:
		return false  # ascending or stationary along gravity's axis -- not falling toward it yet

	var origin: Vector3 = player.global_position
	var target: Vector3 = origin + gravity_dir * landing_predict_ray_length

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [player]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)

	if not hit:
		return false

	var raw_distance: float = (hit.position - origin).length()
	var distance: float = raw_distance - ground_contact_offset

	if distance <= 0.0:
		return true  # already within contact range -- land now

	# Kinematic time-to-impact: distance = v*t + 0.5*a*t^2, solved for
	# t via the quadratic formula. Uses gravity_strength as the
	# acceleration -- an approximation during an active gravity shift
	# (which layers its own acceleration on top of this), but since
	# this re-predicts every physics frame the estimate keeps
	# correcting itself as the player closes in.
	var a: float = max(float(gc.gravity_strength), 0.001)
	var discriminant: float = fall_speed * fall_speed + 2.0 * a * distance
	if discriminant < 0.0:
		return false

	var time_to_land: float = (-fall_speed + sqrt(discriminant)) / a

	return time_to_land <= lead_time


func update(delta: float) -> void:
	if not animation_tree or not anim_playback:
		return

	var on_floor := player.is_on_floor()

	# Preemptive trigger -- start the Land animation before actual
	# touchdown if we're on track to land within its own duration.
	if not on_floor and not land_anim_active:
		if _predict_landing_within(land_anim_duration):
			land_anim_active = true
			current_anim_state = AnimState.LAND
			landing_timer = land_anim_duration
			anim_playback.travel("Land")

	if !was_on_floor and on_floor and not land_anim_active:
		# Touched down without enough warning to have anticipated it
		# (e.g. a very short drop off a low ledge) -- fall back to the
		# old reactive trigger so there's still some landing animation.
		land_anim_active = true
		current_anim_state = AnimState.LAND
		landing_timer = land_anim_duration
		anim_playback.travel("Land")

	was_on_floor = on_floor

	if landing_timer > 0.0:
		landing_timer -= delta
		if landing_timer <= 0.0:
			land_anim_active = false
		_update_locomotion_speed(delta)
		_update_foot_ik(delta)
		return

	land_anim_active = false

	if !on_floor:
		var gravity_state: GravityController.GravityState = player.gravity_controller.gravity_state
		var is_shifting_airborne := gravity_state == GravityController.GravityState.LEVITATING \
			or gravity_state == GravityController.GravityState.SHIFTING

		if is_shifting_airborne:
			if current_anim_state != AnimState.FALL:
				current_anim_state = AnimState.FALL
				anim_playback.travel("Fall")
		elif player.velocity.y > 0.0:
			if current_anim_state != AnimState.JUMP \
			and current_anim_state != AnimState.DOUBLE_JUMP \
			and current_anim_state != AnimState.TRIPLE_JUMP:
				current_anim_state = AnimState.JUMP
				anim_playback.travel("Jump")
		else:
			if current_anim_state != AnimState.FALL:
				current_anim_state = AnimState.FALL
				anim_playback.travel("Fall")
		_update_locomotion_speed(delta)
		_update_foot_ik(delta)
		return

	var was_grounded_locomotion := current_anim_state in [AnimState.IDLE, AnimState.JOG, AnimState.RUN]

	if player.move_input.length_squared() == 0.0:
		current_anim_state = AnimState.IDLE
	elif player.is_running:
		current_anim_state = AnimState.RUN
	else:
		current_anim_state = AnimState.JOG

	if not was_grounded_locomotion:
		anim_playback.travel("BlendSpace1D")

	_update_locomotion_speed(delta)
	animation_tree.set(LOCOMOTION_BLEND_PARAM, smoothed_locomotion_speed)

	_update_foot_ik(delta)


## Tracks the character's real planar speed, lightly smoothed. Kept
## updated even while airborne/landing so that re-entering locomotion
## blends from the speed the body is actually carrying rather than
## from a stale value.
func _update_locomotion_speed(delta: float) -> void:
	var actual_speed: float = player.get_planar_speed()
	var weight: float = 1.0 - exp(-delta / max(speed_blend_smoothing_time, 0.001))
	smoothed_locomotion_speed = lerpf(smoothed_locomotion_speed, actual_speed, weight)

## Call this from Player.gd at the exact frame the double jump is executed.
func play_double_jump() -> void:
	if not animation_tree or not anim_playback:
		return
	current_anim_state = AnimState.DOUBLE_JUMP
	anim_playback.travel("DoubleJump")


## Call this from Player.gd at the exact frame the triple jump is executed.
func play_triple_jump() -> void:
	if not animation_tree or not anim_playback:
		return
	current_anim_state = AnimState.TRIPLE_JUMP
	anim_playback.travel("TripleJump")


func _update_foot_ik(delta: float) -> void:
	if not skeleton or left_bone_idx == -1 or right_bone_idx == -1:
		return

	if not player.is_on_floor():
		left_weight = move_toward(left_weight, 0.0, ik_blend_speed * delta)
		right_weight = move_toward(right_weight, 0.0, ik_blend_speed * delta)
		return

	_solve_foot(left_bone_idx, left_target, delta, true)
	_solve_foot(right_bone_idx, right_target, delta, false)


func _solve_foot(bone_idx: int, target: Node3D, delta: float, is_left: bool) -> void:
	if not target:
		return

	var gravity_dir: Vector3 = player.gravity_controller.gravity_direction
	var foot_global: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx).origin

	var origin := foot_global - gravity_dir * 0.3
	var dest := foot_global + gravity_dir * 0.3

	var query := PhysicsRayQueryParameters3D.create(origin, dest)
	query.exclude = [player]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)

	if not hit:
		return

	var target_position: Vector3 = hit.position - gravity_dir * sole_offset
	var height_above_ground: float = (foot_global - hit.position).length()
	var contact_target: float = 1.0 if height_above_ground < foot_contact_threshold else 0.0

	if is_left:
		left_weight = move_toward(left_weight, contact_target, ik_blend_speed * delta)
		target.global_position = target.global_position.lerp(target_position, left_weight)
	else:
		right_weight = move_toward(right_weight, contact_target, ik_blend_speed * delta)
		target.global_position = target.global_position.lerp(target_position, right_weight)


func force_idle() -> void:
	current_anim_state = AnimState.IDLE
	smoothed_locomotion_speed = 0.0
	if animation_tree and anim_playback:
		anim_playback.travel("BlendSpace1D")
		animation_tree.set(LOCOMOTION_BLEND_PARAM, 0.0)
