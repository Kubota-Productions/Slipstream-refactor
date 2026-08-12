extends SpringArm3D

@export var mouse_sensitivity: float = 0.005
@export var aim_pivot: Node3D
@export var aim_distance: float = 500.0
@export var mouse_aim: Node3D = null
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = 60.0
@export var cam: Camera3D = null
@export var up_smoothing_time: float = 1.0  # seconds for camera "up" to settle after a gravity shift
var smoothed_up: Vector3 = Vector3.UP

var frozen_direction: Vector3 = Vector3.FORWARD
var player: CharacterBody3D
var gravity_controller: GravityController
var is_mouse_aim_frozen: bool = false

var yaw_input: float = 0.0
var pitch_input: float = 0.0
var camera_moved: bool = false
var look_forward: Vector3 = Vector3.FORWARD
var pitch_angle: float = 0.0

var last_up: Vector3 = Vector3.UP

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	player = get_parent()
	gravity_controller = player.get_node("GravityController")

	look_forward = -global_basis.z
	pitch_angle = 0.0
	last_up = Vector3.UP
	smoothed_up = Vector3.UP

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity

func get_boresight_pos() -> Vector3:
	if player:
		var fall_dir: Vector3
		if player.velocity.length_squared() > 0.01:
			fall_dir = player.velocity.normalized()
		else:
			fall_dir = -player.global_transform.basis.z
		return (fall_dir * aim_distance) + player.global_position
	return (-global_transform.basis.z * aim_distance) + global_position

func get_mouse_aim_pos() -> Vector3:
	var x: Vector3
	if is_mouse_aim_frozen:
		if mouse_aim:
			x = mouse_aim.global_position + (frozen_direction * aim_distance)
		else:
			x = global_position + (-global_transform.basis.z * aim_distance)
	else:
		if mouse_aim:
			x = mouse_aim.global_position + (-mouse_aim.global_transform.basis.z * aim_distance)
		else:
			x = global_position + (-global_transform.basis.z * aim_distance)
	return x

# Called explicitly by the player, early in its _physics_process,
# so aim_pivot is guaranteed fresh before movement/orientation read it.
func update_look(delta: float) -> void:
	var target_up: Vector3 = Vector3.UP
	if gravity_controller:
		target_up = -gravity_controller.gravity_direction

	if smoothed_up.dot(target_up) < 0.99999:
		var weight: float = 1.0 - exp(-delta / max(up_smoothing_time, 0.001))
		var full_align: Quaternion = _shortest_arc(smoothed_up, target_up)
		var step_align: Quaternion = Quaternion.IDENTITY.slerp(full_align, weight)
		smoothed_up = (step_align * smoothed_up).normalized()
	else:
		smoothed_up = target_up

	var up: Vector3 = smoothed_up

	# Keep look_forward pinned to the plane perpendicular to "up" every
	# frame -- this is what guarantees zero roll no matter how "up" moves.
	var flat_forward: Vector3 = look_forward.slide(up)
	if flat_forward.length_squared() < 0.0001:
		flat_forward = (-global_basis.x).slide(up)  # forward went parallel to up; fall back to old right
	flat_forward = flat_forward.normalized()

	if yaw_input != 0.0:
		flat_forward = flat_forward.rotated(up, yaw_input).normalized()

	look_forward = flat_forward
	last_up = up

	if pitch_input != 0.0:
		pitch_angle = clamp(
			pitch_angle + pitch_input,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)

	var right: Vector3 = flat_forward.cross(up).normalized()
	var final_forward: Vector3 = flat_forward.rotated(right, pitch_angle).normalized()

	global_basis = Basis.looking_at(final_forward, up)

	if aim_pivot:
		aim_pivot.global_basis = global_basis

	yaw_input = 0.0
	pitch_input = 0.0

func _shortest_arc(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	from_dir = from_dir.normalized()
	to_dir = to_dir.normalized()
	var dot_val := from_dir.dot(to_dir)

	if dot_val > 0.99999:
		return Quaternion.IDENTITY
	if dot_val < -0.99999:
		var axis := from_dir.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.001:
			axis = from_dir.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)

	var axis2 := from_dir.cross(to_dir).normalized()
	var angle := acos(clamp(dot_val, -1.0, 1.0))
	return Quaternion(axis2, angle)
