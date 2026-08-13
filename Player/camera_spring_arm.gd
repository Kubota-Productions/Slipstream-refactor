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
@export var boresight_lag_time: float = 0.05
@export var boresight_jitter_smoothing_time: float = 0.12
var smoothed_boresight_dir: Vector3 = Vector3.FORWARD
var smoothed_boresight_dir_stage2: Vector3 = Vector3.FORWARD

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

@export var camera_3D: Node3D
@export var grounded_spring_length: float = 1.2
@export var shifting_spring_length: float = 3.0
@export var spring_length_smoothing_time: float = 0.25

@export var grounded_shoulder_offset: Vector3 = Vector3(0.4, 0.0, 0.0)
@export var shifting_shoulder_offset: Vector3 = Vector3.ZERO
@export var shoulder_offset_smoothing_time: float = 0.25
@export var smoothed_shoulder_offset: Vector3 = Vector3.ZERO
@export var running_camera_pullback: float = 0.8

@export var grounded_fov: float = 75.0
@export var shifting_fov: float = 90.0
@export var fov_smoothing_time: float = 0.3

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	player = get_parent()
	gravity_controller = player.get_node("GravityController")

	look_forward = -global_basis.z
	pitch_angle = 0.0
	last_up = Vector3.UP
	smoothed_up = Vector3.UP
	spring_length = shifting_spring_length

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity

func get_boresight_pos() -> Vector3:
	if player:
		return (smoothed_boresight_dir_stage2 * aim_distance) + player.global_position
	if camera_3D:
		return (-camera_3D.global_transform.basis.z * aim_distance) + camera_3D.global_position
	return (-global_transform.basis.z * aim_distance) + global_position

func get_mouse_aim_pos() -> Vector3:
	var x: Vector3
	if is_mouse_aim_frozen:
		if mouse_aim:
			x = mouse_aim.global_position + (frozen_direction * aim_distance)
		elif camera_3D:
			x = camera_3D.global_position + (-camera_3D.global_transform.basis.z * aim_distance)
		else:
			x = global_position + (-global_transform.basis.z * aim_distance)
	else:
		if mouse_aim:
			x = mouse_aim.global_position + (-mouse_aim.global_transform.basis.z * aim_distance)
		elif camera_3D:
			x = camera_3D.global_position + (-camera_3D.global_transform.basis.z * aim_distance)
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

	var flat_forward: Vector3 = look_forward.slide(up)
	if flat_forward.length_squared() < 0.0001:
		flat_forward = (-global_basis.x).slide(up)
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

	var use_arm_pitch: bool = gravity_controller \
		and gravity_controller.gravity_state != GravityController.GravityState.GROUNDED

	if use_arm_pitch:
		# Shifting / levitating / wall -- whole arm tilts, old behavior.
		var right: Vector3 = flat_forward.cross(up).normalized()
		var final_forward: Vector3 = flat_forward.rotated(right, pitch_angle).normalized()
		global_basis = Basis.looking_at(final_forward, up)

		if camera_3D:
			camera_3D.rotation = Vector3.ZERO
	else:
		# Grounded -- arm yaws only, camera carries the pitch.
		global_basis = Basis.looking_at(flat_forward, up)

		if camera_3D:
			camera_3D.rotation = Vector3(pitch_angle, 0.0, 0.0)

	if aim_pivot:
		aim_pivot.global_basis = global_basis

	yaw_input = 0.0
	pitch_input = 0.0
	
	_update_boresight_dir(delta)
	_update_camera_distance(delta)

func _update_boresight_dir(delta: float) -> void:
	var target_dir: Vector3
	var snap_instant := false

	if gravity_controller \
	and gravity_controller.gravity_state == GravityController.GravityState.SHIFTING \
	and player and player.velocity.length_squared() > 0.01:
		target_dir = player.velocity.normalized()
		snap_instant = true
	elif camera_3D:
		target_dir = -camera_3D.global_transform.basis.z
	else:
		target_dir = -global_basis.z

	if snap_instant:
		smoothed_boresight_dir = target_dir
		smoothed_boresight_dir_stage2 = target_dir
	else:
		var weight1: float = 1.0 - exp(-delta / max(boresight_lag_time, 0.001))
		smoothed_boresight_dir = smoothed_boresight_dir.slerp(target_dir, weight1).normalized()

		var weight2: float = 1.0 - exp(-delta / max(boresight_jitter_smoothing_time, 0.001))
		smoothed_boresight_dir_stage2 = smoothed_boresight_dir_stage2.slerp(smoothed_boresight_dir, weight2).normalized()

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
	
func _update_camera_distance(delta: float) -> void:
	var target_length: float = shifting_spring_length
	var target_offset: Vector3 = shifting_shoulder_offset
	var target_fov: float = shifting_fov

	if gravity_controller and gravity_controller.gravity_state == GravityController.GravityState.GROUNDED:
		target_length = grounded_spring_length
		target_offset = grounded_shoulder_offset
		target_fov = grounded_fov

	if player and player.is_running:
		target_offset.z += running_camera_pullback

	var length_weight: float = 1.0 - exp(-delta / max(spring_length_smoothing_time, 0.001))
	spring_length = lerp(spring_length, target_length, length_weight)

	var offset_weight: float = 1.0 - exp(-delta / max(shoulder_offset_smoothing_time, 0.001))
	smoothed_shoulder_offset = smoothed_shoulder_offset.lerp(target_offset, offset_weight)

	if camera_3D:
		camera_3D.position = smoothed_shoulder_offset

		var fov_weight: float = 1.0 - exp(-delta / max(fov_smoothing_time, 0.001))
		camera_3D.fov = lerp(camera_3D.fov, target_fov, fov_weight)
