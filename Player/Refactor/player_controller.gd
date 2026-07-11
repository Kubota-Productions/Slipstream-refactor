class_name PlayerController
extends CharacterBody3D

## Reference to the InputHandler node
@export var input_handler: PlayerInputHandler
## Contains the State nodes as children
@export var states_container: Node

## The active camera attached to the PlayerController
@export var active_camera: Camera3D

## The current normal of gravity
var current_gravity_dir: Vector3 = Vector3.DOWN
## The current forward vector of the camera
var camera_aim_vector: Vector3 = Vector3.FORWARD
## The current gravity strength
@export var gravity_strength: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Current PlayerState, defaults to the first child in the state_container.
var current_state: PlayerState


func _ready() -> void:
	# Inject child state nodes with a reference to this node
	for child in states_container.get_children():
		if child is PlayerState:
			child.controller = self
			child.input = input_handler
	change_state(states_container.get_child(0)) # default to first child


func _physics_process(delta: float) -> void:
	# TODO: calculate the current camera aim forward vector from the current camera after apply rotation from input_handler
	if current_state:
		current_state.physics_update(delta)


## Process state change from state reference. If input is null or is the same state, nothing
## will change.
## @param new_state: PlayerState reference to an existing state instance
func change_state(new_state: PlayerState) -> void:
	if current_state == new_state:
		return
	if current_state:
		current_state.exit()
	current_state = new_state
	if current_state:
		current_state.enter()


## Process state change from state reference. Will throw warning on bad state name.
## will change.
## @param new_state: String -> The name state node in the states_container.
func change_state_by_name(state_name: String) -> void:
	var target_state := states_container.get_node_or_null(state_name) as PlayerState
	if target_state:
		change_state(target_state)
	else:
		push_warning("PlayerController: Attempted to transition to null state: " + state_name)


## Helper script for aligning the character to floors.
## @param new_normal: Vector3 -> The normal of the floor to be aligned to
## @param delta: float -> The delta time for the visual rotation
## @param rotation_speed: float -> The speed of the slerp, use to adjust how fast the rotation snaps.
func align_to_surface(new_normal: Vector3, delta: float, rotation_speed: float = 10.0) -> void:
	# Update CharacterBody3D's internal up direction to input
	up_direction = new_normal

	# Smoothly rotate the visual model/collision basis so feet point to the floor
	var current_quat := transform.basis.get_rotation_quaternion()
	var target_basis := _calculate_aligned_basis(new_normal)
	var target_quat := target_basis.get_rotation_quaternion()

	# NOTE: Slerp avoids gimbal lock, very important
	transform.basis = Basis(current_quat.slerp(target_quat, rotation_speed * delta)).orthonormalized()


## Internal helper function for calculating new basis from input vector.
## Pretty self explanatory.
func _calculate_aligned_basis(target_up: Vector3) -> Basis:
	# Get forward vector relative to new up
	var right := transform.basis.y.cross(target_up).normalized()
	if right.is_zero_approx():
		# Fallback is target_up is parallel to current Y
		right = transform.basis.x
	var forward := target_up.cross(right).normalized()
	return Basis(right, target_up, forward)
