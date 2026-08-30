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

	print("anim_playback: ", anim_playback)   # <-- add this
	if not anim_playback:
		push_error("PlayerAnimationController: 'parameters/playback' came back null -- Tree Root probably isn't an AnimationNodeStateMachine")


# Searches by node TYPE rather than name -- immune to renames, casing,
# or Godot auto-appending a suffix to a duplicate-named node.
func _find_first_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found := _find_first_of_type(child, type_name)
		if found:
			return found
	return null


# Debug helper -- only runs on failure, so it's safe to leave in.
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
 

func force_idle() -> void:
	current_anim_state = AnimState.IDLE
	if animation_tree and anim_playback:
		anim_playback.travel("BlendSpace1D")
		animation_tree.set(LOCOMOTION_BLEND_PARAM, 0.0)
