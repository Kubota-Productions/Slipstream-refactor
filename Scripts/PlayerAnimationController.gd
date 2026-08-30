extends Node
class_name PlayerAnimationController

# ============================================================
# REFERENCES
# ============================================================
@export var player: CharacterBody3D
@export var character_model: Node3D

var animation_tree: AnimationTree
var animation_player: AnimationPlayer
var anim_playback: AnimationNodeStateMachinePlayback

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
# STATE
# ============================================================
enum AnimState {
	IDLE,
	JOG,
	RUN,
	JUMP,
	FALL,
	LAND
}

const LANDING_TIME := 0.25
const LOCOMOTION_BLEND_PARAM := "parameters/BlendSpace1D/blend_position"

var current_anim_state := AnimState.IDLE
var was_on_floor := true
var landing_timer := 0.0


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


func _debug_print_tree(root: Node, indent: String = "") -> void:
	print(indent, root.name, "  [", root.get_class(), "]")
	for child in root.get_children():
		_debug_print_tree(child, indent + "  ")


func update(delta: float) -> void:
	if not animation_tree or not anim_playback:
		return

	var on_floor := player.is_on_floor()

	if !was_on_floor and on_floor:
		current_anim_state = AnimState.LAND
		landing_timer = LANDING_TIME
		anim_playback.travel("rig|Land")

	was_on_floor = on_floor

	if landing_timer > 0.0:
		landing_timer -= delta
		_update_foot_ik(delta)
		return

	if !on_floor:
		if player.velocity.y > 0.0:
			if current_anim_state != AnimState.JUMP:
				current_anim_state = AnimState.JUMP
				anim_playback.travel("rig|Jump")
		else:
			if current_anim_state != AnimState.FALL:
				current_anim_state = AnimState.FALL
				anim_playback.travel("rig|Fall")
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

	animation_tree.set(LOCOMOTION_BLEND_PARAM, player.predicted_speed)

	# IK runs last, after the base pose for this frame is fully set --
	# it corrects foot placement on top of whatever the BlendSpace1D produced.
	_update_foot_ik(delta)


func _update_foot_ik(delta: float) -> void:
	if not skeleton or left_bone_idx == -1 or right_bone_idx == -1:
		return

	if not player.is_on_floor():
		# Airborne -- fade IK out, let the base animation drive the legs freely.
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
	if animation_tree and anim_playback:
		anim_playback.travel("BlendSpace1D")
		animation_tree.set(LOCOMOTION_BLEND_PARAM, 0.0)
