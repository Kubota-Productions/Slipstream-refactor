## Responsible for consuming input and storing input state.
## Contains signals for checking state for other components to use.
## THIS CLASS SHOULD NEVER CALL OUTSIDE FUNCTIONS DIRECTLY.
class_name PlayerInputHandler
extends Node

signal jump_pressed()
signal jump_released()
signal run_pressed()
signal run_released()
signal gravity_throw_pressed()

## Private member for storing movement input
var _movement: Vector2 = Vector2.ZERO
## Unit vector representing the intended direction of movement by the player
var movement: Vector2:
	get():
		return _movement

## The delta of the mouse movement from the last frame.
## Use this for making the camera rotate
var _camera_aim_delta: Vector2


func _unhandled_unput(_event: InputEvent) -> void:
	# TODO: Implement input gathering
	pass
