extends SpringArm3D

@export var mouse_sensitivity: float = 0.005
@export var aim_pivot: Node3D
@export var aim_distance: float = 500.0
@export var mouse_aim: Node3D = null
var frozen_direction: Vector3 = Vector3.FORWARD
var player : CharacterBody3D

var is_mouse_aim_frozen: bool = false

var yaw_input: float = 0.0
var pitch_input: float = 0.0
var camera_moved = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity
		
func get_boresight_pos() -> Vector3:
	if player:
		return (player.global_transform.basis.z * aim_distance) + player.global_position
	else: 
		return global_transform.basis.z * aim_distance

func get_mouse_aim_pos() -> Vector3:
	var x: Vector3
	if is_mouse_aim_frozen:
		if mouse_aim:
			x = mouse_aim.global_position + (frozen_direction * aim_distance) 
		else:
			x = global_position + (global_transform.basis.z * aim_distance)
	else:
		if mouse_aim:
			x = mouse_aim.global_position + (mouse_aim.global_transform.basis.z * aim_distance)
		else:
			x = global_position + (global_transform.basis.z * aim_distance)
			
	return x


func _physics_process(delta):

	rotation.x += pitch_input
	rotation.x = clamp(
		rotation.x,
		deg_to_rad(-80),
		deg_to_rad(60)
	)

	rotation.y += yaw_input

	if aim_pivot:
		aim_pivot.rotation = rotation

	yaw_input = 0
	pitch_input = 0
