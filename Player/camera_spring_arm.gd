extends SpringArm3D

var skeleton: Skeleton3D
var head_bone_name: String = "mixamorig_Head"
var root_bone_name: String = "mixamorig_Hips"
var root_bone_idx: int = -1
@export var head_bone_offset: Vector3 = Vector3(0.0, 0.1, 0.0)
@export var pivot_position_smoothing_time: float = 0.03

var head_bone_idx: int = -1
var default_local_position: Vector3 = Vector3.ZERO
var smoothed_pivot_position: Vector3 = Vector3.ZERO

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

@export var ots_transition_time: float = 0.25
var ots_blend_weight: float = 0.0  # 0 = fully "chase" framing, 1 = fully OTS framing

@export var camera_3D: Node3D
@export var grounded_spring_length: float = 1.2
@export var shifting_spring_length: float = 3.0
@export var spring_length_smoothing_time: float = 0.25
@export var wall_spring_length: float = 1.2
@export var wall_shoulder_offset: Vector3 = Vector3(0.4, 0.0, 0.0)
@export var wall_fov: float = 75.0

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

	default_local_position = position
	smoothed_pivot_position = global_position

	skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		head_bone_idx = skeleton.find_bone(head_bone_name)
		root_bone_idx = skeleton.find_bone(root_bone_name)

		var n: Node = skeleton
		while n:
			if n is Node3D:
				print(n.name, " scale: ", (n as Node3D).scale)
			n = n.get_parent()
		
	
	

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

func update_pivot_position(delta: float) -> void:
	var target_position: Vector3

	if skeleton and head_bone_idx != -1 and root_bone_idx != -1:
		var head_pose: Transform3D = skeleton.get_bone_global_pose(head_bone_idx)
		var root_pose: Transform3D = skeleton.get_bone_global_pose(root_bone_idx)
		var relative_offset: Vector3 = skeleton.global_transform.basis * (head_pose.origin - root_pose.origin)
		target_position = player.global_position + relative_offset + head_bone_offset
	else:
		target_position = player.global_position

	var weight: float = 1.0 - exp(-delta / max(pivot_position_smoothing_time, 0.001))
	smoothed_pivot_position = smoothed_pivot_position.lerp(target_position, weight)
	global_position = smoothed_pivot_position
	
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
		and (gravity_controller.gravity_state == GravityController.GravityState.LEVITATING \
			or gravity_controller.gravity_state == GravityController.GravityState.SHIFTING)

	if use_arm_pitch:
		# Levitating / actively shifting through the air -- whole arm tilts.
		var right: Vector3 = flat_forward.cross(up).normalized()
		var final_forward: Vector3 = flat_forward.rotated(right, pitch_angle).normalized()
		global_basis = Basis.looking_at(final_forward, up)

		if camera_3D:
			camera_3D.rotation = Vector3.ZERO
	else:
		# Grounded or attached to a wall -- arm yaws only, camera carries pitch.
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
	var is_grounded: bool = gravity_controller and gravity_controller.gravity_state == GravityController.GravityState.GROUNDED
	var is_wall: bool = gravity_controller and gravity_controller.gravity_state == GravityController.GravityState.WALL

	var target_weight: float = 1.0 if (is_grounded or is_wall) else 0.0

	var blend_speed: float = 1.0 - exp(-delta / max(ots_transition_time, 0.001))
	ots_blend_weight = move_toward(ots_blend_weight, target_weight, blend_speed)

	# OTS side (grounded or wall) vs Chase side (levitating/shifting)
	var ots_length: float = wall_spring_length if is_wall else grounded_spring_length
	var ots_offset: Vector3 = wall_shoulder_offset if is_wall else grounded_shoulder_offset
	var ots_fov: float = wall_fov if is_wall else grounded_fov

	var target_length: float = lerp(shifting_spring_length, ots_length, ots_blend_weight)
	var target_offset: Vector3 = shifting_shoulder_offset.lerp(ots_offset, ots_blend_weight)
	var target_fov: float = lerp(shifting_fov, ots_fov, ots_blend_weight)

	if player and player.is_running:
		target_offset.z += running_camera_pullback

	spring_length = lerp(spring_length, target_length, blend_speed)
	smoothed_shoulder_offset = smoothed_shoulder_offset.lerp(target_offset, blend_speed)

	if camera_3D:
		camera_3D.position = smoothed_shoulder_offset
		camera_3D.fov = lerp(camera_3D.fov, target_fov, blend_speed)
