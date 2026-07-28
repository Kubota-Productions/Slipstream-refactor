extends CharacterBody3D

@onready var visual_root: Node3D = $VisualRoot
@onready var gravity_controller: GravityController = $GravityController
@onready var animation_player: AnimationPlayer = $VisualRoot/CharacterModel/character_mixamo/AnimationPlayer
@onready var animation_tree: AnimationTree = $VisualRoot/AnimationTree
@onready var character_model: Node3D = $VisualRoot/CharacterModel
@onready var spring_arm: SpringArm3D = $VisualRoot/SpringArm3D

#MOVEMENT SETTINGS
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 8.0

@export var jump_velocity: float = 10.0

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
		$VisualRoot/SpringArm3D/Cameraoffset/Camera3D
	)

	gravity_controller.gravity_changed.connect(_on_gravity_changed)

	_play_animation("Armature|idle")

#INPUT
func _unhandled_input(event: InputEvent) -> void:

	if event.is_action_pressed("GravityShift"):
		gravity_controller.enter_levitating()

	if event.is_action_released("GravityShift"):
		gravity_controller.perform_shift()

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
	gravity_controller.update_shift(delta)
	
	move_and_slide()

	gravity_controller.check_wall()

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

func _on_gravity_changed(direction: Vector3) -> void:

	up_direction = -direction

	var current_forward = -visual_root.global_basis.z
	var projected_forward = current_forward.slide(up_direction).normalized()

	if projected_forward.length() < 0.01:
		projected_forward = visual_root.global_basis.x

	var target_basis = Basis.looking_at(
		projected_forward,
		up_direction
	)

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		visual_root,
		"basis",
		target_basis,
		0.35
	)
	
#GRAVITY
func _apply_gravity(delta):

	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	if gravity_controller.gravity_state == GravityController.GravityState.GROUNDED \
	or gravity_controller.gravity_state == GravityController.GravityState.WALL:

		var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

		velocity += gravity_controller.gravity_direction * gravity * delta

#JUMP
func _handle_jump(_delta: float) -> void:

	# Jump
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:

		velocity -= gravity_controller.gravity_direction * jump_velocity

		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# Variable jump height
	var vertical_speed = velocity.dot(-gravity_controller.gravity_direction)

	if Input.is_action_just_released("Jump") and vertical_speed > 0.0:
		velocity += gravity_controller.gravity_direction * (vertical_speed * 0.5)

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

			rotate_object_local(up_direction, spring_arm.yaw_input)

	else:

		spring_arm.rotate_object_local(up_direction, spring_arm.yaw_input)

#MOVEMENT
func _handle_movement(delta: float) -> void:

	if move_input.length_squared() > 0.0:

		var input_direction := Vector3(
			move_input.x,
			0.0,
			move_input.y
		).normalized()

		var cam_basis = spring_arm.global_basis

		var forward = cam_basis.z.slide(up_direction).normalized()
		var right = cam_basis.x.slide(up_direction).normalized()

		move_direction = forward * move_input.y + right * move_input.x

		move_direction = move_direction.normalized()

		current_speed = run_speed if is_running else walk_speed

		var desired_velocity := move_direction * current_speed

		var air_control := 0.45 if !is_on_floor() else 1.0

		# Split velocity into vertical and horizontal components
		var vertical_velocity := up_direction * velocity.dot(up_direction)
		var horizontal_velocity := velocity - vertical_velocity

		# Smoothly move toward the desired horizontal velocity
		horizontal_velocity = horizontal_velocity.lerp(
			desired_velocity,
			acceleration * air_control * delta
		)

		# Recombine them
		velocity = horizontal_velocity + vertical_velocity

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
