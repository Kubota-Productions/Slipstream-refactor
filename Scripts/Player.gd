class_name Player
extends CharacterBody3D

# ============================================================
# REFERENCES
# ============================================================
@onready var gravity_controller: GravityController = $GravityController
@onready var character_model: Node3D = $CharacterModel
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Cameraoffset/Camera3D
@onready var aim_pivot: Node3D = $"../AimPivot"

@export var animation_controller: Node  # assign the AnimationController node in the editor

# ============================================================
# MOVEMENT
# ============================================================
@export_group("Movement")
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var speed_acceleration: float = 8.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 8.0
@export var max_landing_speed: float = 8.0

const RUN_THRESHOLD := 0.40

var move_input: Vector2 = Vector2.ZERO
var move_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var is_running := false
var run_timer := 0.0

# ============================================================
# JUMPING
# ============================================================
@export_group("Jumping")
@export var jump_velocity: float = 10.0
@export var gravity_multiplier: float = 1.0
@export var coyote_time: float = 0.15
@export var jump_buffer: float = 0.15
@export var max_jumps: int = 2

var jumps_used: int = 0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var was_grounded_last_frame := true

# ============================================================
# OTS EXPLORE MODE
# A separate, orthogonal camera/input mode toggled by right click.
# It does NOT replace or plug into GravityController's state machine
# -- traversal (running/jumping/shifting) keeps using that as before.
# This mode only exists to let the player stop, walk slowly, and
# freely look around in a dedicated over-the-shoulder framing.
# ============================================================
@export_group("OTS Explore Mode")
var is_ots_mode: bool = false

# ============================================================
# TRAJECTORY PREDICTION  (consumed by the animation controller)
# ============================================================
@export_group("Trajectory Prediction")
@export var prediction_horizon: float = 0.15
@export var prediction_substep: float = 0.02

var turn_rate: float = 0.0
var predicted_speed: float = 0.0
var predicted_turn_rate: float = 0.0
var prev_model_forward: Vector3 = Vector3.FORWARD

# ============================================================
# DEBUG
# ============================================================
@export_group("Debug")
@export var debug_print_state := false


# ============================================================
# LIFECYCLE
# ============================================================
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	gravity_controller.setup(
		self,
		$SpringArm3D/Cameraoffset/Camera3D
	)


func _unhandled_input(event: InputEvent) -> void:

	if event.is_action_pressed("ToggleOTS"):
		if is_ots_mode:
			is_ots_mode = false
		elif gravity_controller.gravity_state == GravityController.GravityState.GROUNDED:
			is_ots_mode = true

	# Jumping and gravity-shifting are entirely off-limits while
	# exploring -- gate them here so there's no path to trigger them.
	if not is_ots_mode:
		if event.is_action_pressed("GravityShift"):
			gravity_controller.enter_levitating()

		if event.is_action_released("GravityShift"):
			gravity_controller.begin_shift()

		if event.is_action_pressed("CancelShift"):
			if gravity_controller.gravity_state == GravityController.GravityState.SHIFTING \
			or gravity_controller.gravity_state == GravityController.GravityState.WALL:
				gravity_controller.return_to_ground()

	if event is InputEventMouseMotion:

		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

		if move_input == Vector2.ZERO and !spring_arm.camera_moved:

			var yaw_delta: float = -event.relative.x * spring_arm.mouse_sensitivity

			if abs(yaw_delta) > 0.01:
				spring_arm.camera_moved = true


func _physics_process(delta: float) -> void:

	aim_pivot.global_position = global_position
	spring_arm.update_look(delta)

	_read_input(delta)
	_apply_gravity(delta)

	# OTS mode is grounded-only -- if the player walks off a ledge or
	# otherwise leaves the floor, drop straight back to the normal
	# traversal camera instead of leaving the player stuck mid-air
	# in a walk-only, no-jump, no-shift state.
	if is_ots_mode and not is_on_floor():
		is_ots_mode = false

	gravity_controller.update_shift_power(delta)
	_handle_movement(delta)
	_handle_jump(delta)

	if gravity_controller.gravity_state == GravityController.GravityState.SHIFTING:
		gravity_controller.update_shift(delta)
	elif gravity_controller.gravity_state == GravityController.GravityState.LEVITATING:
		gravity_controller.update_levitating(delta)

	if gravity_controller.gravity_state != GravityController.GravityState.GROUNDED:
		_update_orientation(delta)

	move_and_slide()

	gravity_controller.detect_wall()

	spring_arm.update_pivot_position(delta)

	_predict_trajectory(delta)

	# Animation reads fully-updated physics state for this frame.
	if animation_controller:
		animation_controller.update(delta)


# ============================================================
# INPUT HANDLING
# ============================================================
func _read_input(delta: float) -> void:

	move_input.x = Input.get_axis("left", "right")
	move_input.y = Input.get_axis("forward", "backwards")

	if is_ots_mode:
		# Walk-only while exploring -- no running, no buffered jumps.
		run_timer = 0.0
		is_running = false
		jump_buffer_timer = 0.0
		return

	if Input.is_action_pressed("Run"):
		run_timer += delta

		if run_timer >= RUN_THRESHOLD:
			is_running = true
	else:
		run_timer = 0.0
		is_running = false

	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer

	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta


# ============================================================
# GRAVITY
# ============================================================
func _apply_gravity(delta):

	if is_on_floor():
		if not was_grounded_last_frame:
			var up: Vector3 = -gravity_controller.gravity_direction
			var planar_velocity: Vector3 = velocity.slide(gravity_controller.gravity_direction)
			if planar_velocity.length() > max_landing_speed:
				planar_velocity = planar_velocity.normalized() * max_landing_speed
			velocity = planar_velocity + velocity.project(gravity_controller.gravity_direction)

		coyote_timer = coyote_time
		jumps_used = 0
	else:
		coyote_timer -= delta

	was_grounded_last_frame = is_on_floor()

	gravity_controller.apply_gravity(delta)

# ============================================================
# JUMP
# ============================================================
func _handle_jump(delta: float) -> void:

	if jump_buffer_timer > 0.0:

		if coyote_timer > 0.0:
			velocity -= gravity_controller.gravity_direction * jump_velocity
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			jumps_used = 1

		elif jumps_used < max_jumps:
			var up: Vector3 = -gravity_controller.gravity_direction
			velocity -= velocity.project(up)
			velocity += up * jump_velocity

			jump_buffer_timer = 0.0

			if animation_controller:
				match jumps_used:
					1:
						animation_controller.play_double_jump()
					2:
						animation_controller.play_triple_jump()

			jumps_used += 1

# ============================================================
# ORIENTATION
# ============================================================
func _update_orientation(delta: float) -> void:

	var up := -gravity_controller.gravity_direction

	var forward: Vector3 = -aim_pivot.global_basis.z
	forward = forward.slide(up)

	if forward.length_squared() < 0.001:
		return

	forward = forward.normalized()

	var target_basis := Basis.looking_at(forward, up)

	global_basis = Basis(
		global_basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			delta * 5.0
		)
	)


# ============================================================
# SHARED TARGET MOTION  (used by both real movement and the predictor)
# ============================================================
func _get_target_motion() -> Dictionary:
	var gravity_up := -gravity_controller.gravity_direction

	if move_input.length_squared() == 0.0:
		return {
			"target_velocity": Vector3.ZERO,
			"target_forward": (-character_model.global_basis.z).slide(gravity_up).normalized()
		}

	var camera_forward: Vector3 = aim_pivot.global_basis.z
	camera_forward = camera_forward.slide(gravity_up)
	if camera_forward.length_squared() > 0.001:
		camera_forward = camera_forward.normalized()

	var camera_right: Vector3 = aim_pivot.global_basis.x
	camera_right = camera_right.slide(gravity_up)
	if camera_right.length_squared() > 0.001:
		camera_right = camera_right.normalized()

	var dir := (camera_forward * move_input.y + camera_right * move_input.x).normalized()
	var spd := run_speed if is_running else walk_speed

	return {
		"target_velocity": dir * spd,
		"target_forward": dir
	}


# ============================================================
# MOVEMENT
# ============================================================
func _handle_movement(delta: float) -> void:

	if move_input.length_squared() > 0.0:

		var target := _get_target_motion()
		var target_velocity: Vector3 = target["target_velocity"]
		move_direction = target["target_forward"]
		current_speed = run_speed if is_running else walk_speed

		var air_control := 0.45 if !is_on_floor() else 1.0

		var current_planar_velocity = velocity.slide(gravity_controller.gravity_direction)
		var target_planar_velocity = target_velocity.slide(gravity_controller.gravity_direction)

		current_planar_velocity = current_planar_velocity.lerp(
			target_planar_velocity,
			acceleration * air_control * delta
		)

		velocity = current_planar_velocity + (
			velocity.project(gravity_controller.gravity_direction)
		)

		var up := -gravity_controller.gravity_direction
		var target_forward := move_direction.slide(up).normalized()

		if target_forward.length_squared() > 0.001:
			var target_basis := Basis.looking_at(target_forward, up)
			character_model.global_basis = Basis(
				character_model.global_basis
				.get_rotation_quaternion()
				.slerp(target_basis.get_rotation_quaternion(), rotation_speed * delta)
			)

	else:
		var planar_velocity: Vector3 = velocity.slide(gravity_controller.gravity_direction)
		planar_velocity = planar_velocity.move_toward(Vector3.ZERO, acceleration * delta)
		velocity = planar_velocity + velocity.project(gravity_controller.gravity_direction)

	_update_turn_rate(delta)


func _update_turn_rate(delta: float) -> void:
	var up := -gravity_controller.gravity_direction
	var forward := (-character_model.global_basis.z).slide(up).normalized()

	if prev_model_forward.length_squared() > 0.0001 and forward.length_squared() > 0.0001:
		var cross := prev_model_forward.cross(forward)
		var signed_angle := atan2(cross.dot(up), prev_model_forward.dot(forward))
		var instant_rate: float = signed_angle / max(delta, 0.0001)
		turn_rate = lerp(turn_rate, instant_rate, 1.0 - exp(-10.0 * delta))

	prev_model_forward = forward


func _predict_trajectory(delta: float) -> void:
	var target := _get_target_motion()
	var target_velocity: Vector3 = target["target_velocity"]
	var target_forward: Vector3 = target["target_forward"]

	var gravity_up := -gravity_controller.gravity_direction
	var air_control := 0.45 if !is_on_floor() else 1.0

	var sim_velocity: Vector3 = velocity.slide(gravity_controller.gravity_direction)
	var sim_forward: Vector3 = (-character_model.global_basis.z).slide(gravity_up).normalized()
	var start_forward := sim_forward

	var safe_substep: float = max(prediction_substep, 0.005)   # never 0, never near-0
	var steps: int = int(ceil(prediction_horizon / safe_substep))
	var actual_step: float = prediction_horizon / float(steps)

	for i in steps:
		sim_velocity = sim_velocity.lerp(target_velocity, acceleration * air_control * actual_step)

		if target_forward.length_squared() > 0.001 and sim_forward.length_squared() > 0.001:
			var current_basis := Basis.looking_at(sim_forward, gravity_up)
			var target_basis := Basis.looking_at(target_forward, gravity_up)
			var stepped_quat := current_basis.get_rotation_quaternion().slerp(
				target_basis.get_rotation_quaternion(), rotation_speed * actual_step
			)
			sim_forward = -(Basis(stepped_quat).z)

	predicted_speed = sim_velocity.length()

	if start_forward.length_squared() > 0.0001 and sim_forward.length_squared() > 0.0001:
		var cross := start_forward.cross(sim_forward)
		var signed_angle := atan2(cross.dot(gravity_up), start_forward.dot(sim_forward))
		predicted_turn_rate = signed_angle / max(prediction_horizon, 0.0001)


# ============================================================
# HELPERS
# ============================================================
func is_moving() -> bool:
	return move_input.length_squared() > 0.001


func force_idle() -> void:
	velocity = Vector3.ZERO
	move_input = Vector2.ZERO
	run_timer = 0.0
	is_running = false

	if animation_controller:
		animation_controller.force_idle()


func stop_horizontal_velocity() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func launch(direction: Vector3, force: float) -> void:
	velocity += direction.normalized() * force


func set_running(enabled: bool) -> void:
	is_running = enabled
	if !enabled:
		run_timer = 0.0
