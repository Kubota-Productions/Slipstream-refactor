extends CharacterBody3D

@onready var gravity_controller: GravityController = $GravityController
@onready var animation_player: AnimationPlayer = $CharacterModel/character_mixamo/AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var character_model: Node3D = $CharacterModel
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera_3d: Camera3D = $SpringArm3D/Cameraoffset/Camera3D


#MOVEMENT SETTINGS
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 8.0

@export var jump_velocity: float = 10.0
@export var gravity_multiplier: float = 1.0

@export var coyote_time: float = 0.15
@export var jump_buffer: float = 0.15

const RUN_THRESHOLD := 0.40

#STATE
var move_input: Vector2 = Vector2.ZERO
var move_direction: Vector3 = Vector3.ZERO

var current_speed: float = 0.0

var is_running := false
var run_timer := 0.0

var coyote_timer := 0.0
var jump_buffer_timer := 0.0

enum AnimState {
	IDLE,
	JOG,
	RUN,
	JUMP,
	FALL,
	LAND
}

var current_anim_state := AnimState.IDLE

var was_on_floor := true
var landing_timer := 0.0

const LANDING_TIME := 0.25

# READY
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	gravity_controller.setup(
		self,
		$SpringArm3D/Cameraoffset/Camera3D
	)

	_play_animation("Armature|idle")

#INPUT
func _unhandled_input(event: InputEvent) -> void:

	if event.is_action_pressed("GravityShift"):
		gravity_controller.enter_levitating()

	if event.is_action_released("GravityShift"):
		gravity_controller.begin_shift()

	if event is InputEventMouseMotion:

		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

		if move_input == Vector2.ZERO and !spring_arm.camera_moved:

			var yaw_delta: float = -event.relative.x * spring_arm.mouse_sensitivity

			if abs(yaw_delta) > 0.01:
				spring_arm.camera_moved = true

#PHYSICS
func _physics_process(delta: float) -> void:

	_read_input(delta)
	_apply_gravity(delta)
	_handle_movement(delta)
	_handle_jump(delta)
	_handle_rotation()
	if gravity_controller.gravity_state == GravityController.GravityState.SHIFTING:
		gravity_controller.update_shift(delta)
	_update_orientation(delta)
	move_and_slide()

	gravity_controller.detect_wall()

	_update_animation(delta)

#INPUT HANDLING
func _read_input(delta: float) -> void:

	move_input.x = Input.get_axis("left", "right")
	move_input.y = Input.get_axis("forward", "backwards")

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

#GRAVITY
func _apply_gravity(delta):

	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	gravity_controller.apply_gravity(delta)

#JUMP
func _handle_jump(delta: float) -> void:

	# Jump if we're on the floor (or within coyote time)
	# and the player pressed jump recently.
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:

		velocity -= gravity_controller.gravity_direction * jump_velocity

		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# Variable jump height.
	# Releasing Jump while moving upward cuts the jump short.
	if Input.is_action_just_released("Jump") and velocity.y > 0.0:
		velocity.y *= 0.5

#ROTATION
func _handle_rotation() -> void:

	if move_input.length_squared() > 0.0:

		if spring_arm.camera_moved:

			var target_yaw := spring_arm.global_rotation.y

			var player_rotation := global_rotation
			player_rotation.y = target_yaw
			global_rotation = player_rotation

			spring_arm.rotation.y = 0.0
			spring_arm.camera_moved = false

		else:

			rotate_y(spring_arm.yaw_input)

	else:

		spring_arm.rotate_y(spring_arm.yaw_input)

func _update_orientation(delta: float) -> void:

	var up := -gravity_controller.gravity_direction

	var forward := -global_basis.z

	# Remove the component pointing into gravity
	forward = forward.slide(up)

	if forward.length_squared() < 0.001:
		return

	forward = forward.normalized()

	var target_basis := Basis.looking_at(
		forward,
		up
	)

	global_basis = Basis(
		global_basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			delta * 6.0
		)
	)

#MOVEMENT
func _handle_movement(delta: float) -> void:

	if move_input.length_squared() > 0.0:

		var input_direction := Vector3(
			move_input.x,
			0.0,
			move_input.y
		).normalized()

		move_direction = global_transform.basis * input_direction
		move_direction = move_direction.normalized()

		var forward = camera_3d.global_basis.z
		forward = forward.slide(gravity_controller.gravity_direction).normalized()

		var right = camera_3d.global_basis.x
		right = right.slide(gravity_controller.gravity_direction).normalized()

		move_direction = forward * move_input.y + right * move_input.x
	
		current_speed = run_speed if is_running else walk_speed

		var target_velocity := move_direction * current_speed

		var air_control := 0.45 if !is_on_floor() else 1.0

		velocity.x = lerp(
			velocity.x,
			target_velocity.x,
			acceleration * air_control * delta
		)

		velocity.z = lerp(
			velocity.z,
			target_velocity.z,
			acceleration * air_control * delta
		)

		var target_rotation := atan2(
			move_direction.x,
			move_direction.z
		)

		character_model.rotation.y = lerp_angle(
			character_model.rotation.y,
			target_rotation - rotation.y,
			rotation_speed * delta
		)

	else:

		velocity.x = move_toward(
			velocity.x,
			0.0,
			acceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			acceleration * delta
		)

#ANIMATION
func _update_animation(delta: float) -> void:

	# Detect landing
	if !was_on_floor and is_on_floor():
		current_anim_state = AnimState.LAND
		landing_timer = LANDING_TIME
		_play_animation("Armature|gravity_to_idle")

	was_on_floor = is_on_floor()

	# Let the landing animation finish
	if landing_timer > 0.0:
		landing_timer -= delta
		return

	# Airborne
	if !is_on_floor():

		if velocity.y > 0.0:

			if current_anim_state != AnimState.JUMP:
				current_anim_state = AnimState.JUMP

				if move_input.length_squared() > 0.0:
					_play_animation("Armature|run_jump")
				else:
					_play_animation("Armature|jump")

		else:

			if current_anim_state != AnimState.FALL:
				current_anim_state = AnimState.FALL
				_play_animation("Armature|falling_1")

		return

	# Grounded

	if move_input.length_squared() == 0.0:

		if current_anim_state != AnimState.IDLE:
			current_anim_state = AnimState.IDLE
			_play_animation("Armature|idle")

	elif is_running:

		if current_anim_state != AnimState.RUN:
			current_anim_state = AnimState.RUN
			_play_animation("Armature|run")

	else:

		if current_anim_state != AnimState.JOG:
			current_anim_state = AnimState.JOG
			_play_animation("Armature|jog")

#PLAY ANIMATION
func _play_animation(anim_name: String) -> void:

	if animation_player.current_animation == anim_name \
	and animation_player.is_playing():
		return

	animation_player.play(anim_name)

#HELPERS
func is_moving() -> bool:
	return move_input.length_squared() > 0.001

#OPTIONAL CAMERA IMPROVEMENTS
func _process(_delta: float) -> void:

	# Keep the camera's local pitch within a sensible range.
	# (Yaw is already handled by your SpringArm script.)
	spring_arm.rotation.x = clamp(
		spring_arm.rotation.x,
		deg_to_rad(-80.0),
		deg_to_rad(70.0)
	)

#OPTIONAL HELPERS
func force_idle() -> void:

	velocity = Vector3.ZERO
	move_input = Vector2.ZERO
	run_timer = 0.0
	is_running = false

	current_anim_state = AnimState.IDLE
	_play_animation("Armature|idle")


func stop_horizontal_velocity() -> void:

	velocity.x = 0.0
	velocity.z = 0.0


func launch(direction: Vector3, force: float) -> void:

	velocity += direction.normalized() * force


func set_running(enabled: bool) -> void:

	is_running = enabled

	if !enabled:
		run_timer = 0.0

#DEBUG
@export var debug_print_state := false

func _physics_process_debug() -> void:

	if !debug_print_state:
		return

	print(
		"Floor:", is_on_floor(),
		" | Run:", is_running,
		" | Speed:", current_speed,
		" | Y:", snapped(velocity.y, 0.01),
		" | State:", current_anim_state
	)
