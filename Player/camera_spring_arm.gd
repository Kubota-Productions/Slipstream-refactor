extends SpringArm3D

@export var mouse_sensitivity: float = 0.005
@export var aim_pivot: Node3D
@export var aim_distance: float = 500.0
@export var mouse_aim: Node3D = null
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = 60.0
@export var cam: Camera3D = null

var frozen_direction: Vector3 = Vector3.FORWARD
var player: CharacterBody3D
var gravity_controller: GravityController
var is_mouse_aim_frozen: bool = false

var yaw_input: float = 0.0
var pitch_input: float = 0.0
var camera_moved: bool = false

var look_quat: Quaternion = Quaternion.IDENTITY
var last_up: Vector3 = Vector3.UP

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	player = get_parent()
	gravity_controller = player.get_node("GravityController")

	look_quat = global_basis.get_rotation_quaternion()
	last_up = Vector3.UP

func _physics_process(delta: float) -> void:

	print("player physics running")

	update_look(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity

func get_boresight_pos() -> Vector3:
	if player:
		return (-player.global_transform.basis.z * aim_distance) + player.global_position
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
func update_look(_delta: float) -> void:
	var up: Vector3 = Vector3.UP
	if gravity_controller:
		up = -gravity_controller.gravity_direction
		print("Yaw/Pitch:", yaw_input, pitch_input)
		print("Forward:", -global_basis.z)

	# Gravity direction changed since last frame: re-anchor the stored
	# orientation with a minimal "swing" rotation instead of rebuilding
	# it from scratch. This is what removes the shift jitter — yaw/pitch
	# carry over smoothly instead of snapping to a new reference frame.
	if up.dot(last_up) < 0.9999:
		var align_rot: Quaternion = _shortest_arc(last_up, up)
		look_quat = (align_rot * look_quat).normalized()
	last_up = up

	if yaw_input != 0.0:
		var yaw_rot := Quaternion(up, yaw_input)
		look_quat = (yaw_rot * look_quat).normalized()

	if pitch_input != 0.0:
		var right: Vector3 = look_quat * Vector3.RIGHT
		var pitch_rot := Quaternion(right, pitch_input)
		var candidate := (pitch_rot * look_quat).normalized()

		var forward: Vector3 = candidate * Vector3.FORWARD
		var new_pitch: float = asin(clamp(forward.dot(up), -1.0, 1.0))

		if new_pitch <= deg_to_rad(max_pitch_deg) and new_pitch >= deg_to_rad(min_pitch_deg):
			look_quat = candidate
		# else: outside clamp range, just drop this frame's pitch delta

	global_basis = Basis(look_quat)

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
