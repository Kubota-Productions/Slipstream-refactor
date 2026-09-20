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
@onready var telekinesis_controller: TelekinesisController = $TelekinesisController

@export var animation_controller: Node  # assign the AnimationController node in the editor

# ============================================================
# ACCELERATION ACCUMULATOR
# ============================================================
# Velocity is mutated in exactly ONE place: _integrate_velocity(),
# which runs once per physics frame immediately before
# move_and_slide() and does the single "v += a * delta" step.
#
# Every system that wants to affect motion -- movement input, gravity,
# gravity shifting, levitation, landing braking -- contributes an
# acceleration to this accumulator instead of assigning to velocity.
# Nothing snaps, because an acceleration can only ever change velocity
# by (a * delta) in a frame; there is no code path that can set a
# velocity component straight to a value.
#
# The handful of genuine exceptions (respawns, wall-attach teleports)
# go through hard_stop()/rotate_velocity() so they're explicit and
# greppable rather than scattered assignments.
# ============================================================
var pending_acceleration: Vector3 = Vector3.ZERO
var _current_delta: float = 0.016


## Returns the acceleration that moves `current` toward `target` as
## fast as `max_accel` allows, without ever overshooting it.
##
## This is the workhorse that replaces every lerp()/move_toward() that
## used to be applied straight to velocity. A naive
## "(target - current).normalized() * max_accel" would never settle --
## it applies full force right up to the target, blows past it, then
## applies full force back the other way, oscillating forever. So:
## first work out the acceleration that would land exactly on target
## this frame, and only clamp it when that exceeds max_accel. Far from
## the target that's a constant-force approach; close in it eases down
## and settles.
static func acceleration_toward(
	current: Vector3,
	target: Vector3,
	max_accel: float,
	delta: float
) -> Vector3:
	var needed: Vector3 = (target - current) / max(delta, 0.0001)

	if needed.length() > max_accel:
		return needed.normalized() * max_accel

	return needed


## Contribute an acceleration (units/sec^2) for this frame.
func add_acceleration(accel: Vector3) -> void:
	pending_acceleration += accel


## Contribute an instantaneous velocity change (units/sec) -- a jump,
## a launch pad, a knockback. Routed through the same accumulator (as
## accel = impulse/delta, which integrates back to exactly the
## impulse) so velocity still has a single mutation point. Impulses
## are deliberately still supported: a jump genuinely IS an impulse,
## and modelling one as a sustained force would make jump height
## depend on frame timing and be far harder to tune.
func add_impulse(impulse: Vector3) -> void:
	pending_acceleration += impulse / max(_current_delta, 0.0001)


func _integrate_velocity(delta: float) -> void:
	velocity += pending_acceleration * delta
	pending_acceleration = Vector3.ZERO


## Hard velocity reset. An intentional exception to the acceleration
## model, for events where the body is being repositioned/teleported
## rather than moving continuously (wall attach, respawn, cutscene) --
## carrying momentum across a teleport is wrong, not smooth.
func hard_stop() -> void:
	velocity = Vector3.ZERO
	pending_acceleration = Vector3.ZERO


## Rotates existing velocity without changing its magnitude. Used when
## the gravity frame itself rotates (wall following) -- the character's
## momentum is being reinterpreted in a new basis, not accelerated.
func rotate_velocity(rotation: Quaternion) -> void:
	velocity = rotation * velocity

# ============================================================
# ROTATION PIVOT
# ============================================================
# A CharacterBody3D's origin is usually at the FEET, but the body
# should rotate about its CENTER. Assigning global_basis directly
# pivots around the origin, which swings the whole capsule through an
# arc centred on the feet -- so flipping upright while stuck to a
# ceiling sweeps the body up into the ceiling geometry and clips.
#
# set_basis_preserving_center() instead holds the collision shape's
# world-space centre fixed and rotates around that, then corrects
# global_position to match. The body spins in place rather than
# swinging, so no part of it travels further than its own radius.
# ============================================================
## Optional. Auto-detected from the first CollisionShape3D child if
## left unassigned -- a CollisionShape3D's local position IS the
## centre of its shape, which is exactly the offset needed here.
@export var collision_shape: CollisionShape3D
## Overrides the auto-detected centre offset (local space, origin ->
## collision centre) when set to anything other than zero.
@export var body_center_offset_override: Vector3 = Vector3.ZERO

var body_center_offset: Vector3 = Vector3.ZERO


func _resolve_body_center_offset() -> void:
	if body_center_offset_override != Vector3.ZERO:
		body_center_offset = body_center_offset_override
		return

	if not collision_shape:
		for child in get_children():
			if child is CollisionShape3D:
				collision_shape = child
				break

	if collision_shape:
		body_center_offset = collision_shape.position
	else:
		push_warning("Player: no CollisionShape3D found -- rotation will pivot around the body origin (feet), which can clip geometry when flipping upright. Set body_center_offset_override.")
		body_center_offset = Vector3.ZERO


## Current world-space position of the collision shape's centre.
func get_body_center() -> Vector3:
	return global_position + global_basis * body_center_offset


## Sets global_basis while holding the body's CENTRE still, adjusting
## global_position so the centre doesn't move. Use this anywhere the
## character's orientation changes while it's standing in the world --
## direct global_basis assignment pivots around the feet and clips.
func set_basis_preserving_center(new_basis: Basis) -> void:
	var world_center: Vector3 = get_body_center()
	global_basis = new_basis
	global_position = world_center - new_basis * body_center_offset

# ============================================================
# MOVEMENT
# ============================================================
@export_group("Movement")
@export var walk_speed: float = 2.5
@export var run_speed: float = 5.0
@export var speed_acceleration: float = 8.0
## NOTE: now a REAL acceleration in units/sec^2, not the old lerp
## weight. The old value (10.0) was a blend factor and does not carry
## over -- these will need retuning. As a starting point, reaching
## run_speed (5.0) in ~0.15s needs roughly 5/0.15 = 33 units/sec^2.
@export var move_acceleration: float = 35.0
## Separate, usually higher than move_acceleration so the character
## stops more crisply than it starts. Applied when there's no input.
@export var move_deceleration: float = 45.0
@export var rotation_speed: float = 8.0
## Braking acceleration applied after a hard landing. Replaces the old
## hard velocity clamp on the landing frame -- same intent, but bleeds
## the speed off over a few frames instead of snapping it.
@export var landing_brake_acceleration: float = 60.0
## Only speed carried in from a FALL gets braked, and only for this
## long after touchdown. Deliberately not a continuous grounded speed
## cap: ordinary locomotion is already limited by its own target
## speed, so a permanent cap here would just fight power sprinting
## (which exceeds max_landing_speed by design) and silently pin it.
@export var landing_brake_time: float = 0.3
@export var max_landing_speed: float = 8.0

var landing_brake_timer: float = 0.0
@export var run_ramp_time: float = 0.35
@export var power_sprint_speed: float = 9.0
@export var power_sprint_ramp_time: float = 0.25
## Grip while power sprinting. At high speed the same acceleration
## takes proportionally longer to change or kill momentum, which is
## what reads as "slidey" -- so the sprint scales its own accel and
## decel up to compensate. These blend in with power_blend, so they
## only apply as much as the sprint is actually engaged.
@export var power_sprint_acceleration_multiplier: float = 1.8
@export var power_sprint_deceleration_multiplier: float = 2.5

# ============================================================
# RUN DUST
# ============================================================
@export_group("Run Dust")
@export var Particle_Controller: ParticleController

var move_input: Vector2 = Vector2.ZERO
var move_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var is_running := false
var is_power_sprinting := false
var run_timer := 0.0
var run_blend: float = 0.0
var power_blend: float = 0.0

const RUN_THRESHOLD := 0.40

@export_group("Lean")
@export var lean_max_angle_deg: float = 20.0
@export var lean_smoothing_speed: float = 6.0
@export var lean_turn_rate_reference: float = 3.0  # turn_rate (rad/s) that maps to full lean
## Lean angle is multiplied by this at top speed, so the character
## banks harder the faster they're going rather than just reaching the
## same max angle sooner. 1.0 disables the effect.
@export var lean_high_speed_multiplier: float = 1.8
## Shapes how lean ramps in across the speed range. Above 1.0 keeps
## lean subtle at walking pace and saves most of it for genuinely
## fast movement; 1.0 is a straight linear ramp.
@export var lean_speed_curve_power: float = 1.5

var model_yaw_basis: Basis = Basis.IDENTITY
var current_lean: float = 0.0
# ============================================================
# JUMPING
# ============================================================
@export_group("Jumping")
@export var jump_velocity: float = 10.0
@export var gravity_multiplier: float = 1.0
@export var coyote_time: float = 0.15
@export var jump_buffer: float = 0.15
@export var max_jumps: int = 2
## Gravity meter cost for each jump PAST the first (double jump, triple
## jump, etc). The initial ground/coyote jump is always free -- only
## the extra air jumps draw from shift_power, and if there isn't
## enough available, the extra jump simply doesn't happen.
@export var air_jump_power_cost: float = 15.0

var jumps_used: int = 0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var was_grounded_last_frame := true

# ============================================================
# OTS EXPLORE MODE
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
# LIFECYCLE
# ============================================================
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	model_yaw_basis = character_model.global_basis

	_resolve_body_center_offset()

	gravity_controller.setup(
		self,
		$SpringArm3D/Cameraoffset/Camera3D
	)

	telekinesis_controller.setup(self, camera_3d)

	if Particle_Controller:
		Particle_Controller.setup(self)


func _unhandled_input(event: InputEvent) -> void:

	if event.is_action_pressed("ToggleOTS"):
		if is_ots_mode:
			is_ots_mode = false
		elif gravity_controller.gravity_state == GravityController.GravityState.GROUNDED:
			is_ots_mode = true

	telekinesis_controller.handle_input(event)

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

	_current_delta = delta

	aim_pivot.global_position = global_position
	spring_arm.update_look(delta)

	_read_input(delta)
	_apply_gravity(delta)

	if is_ots_mode and not is_on_floor():
		is_ots_mode = false

	gravity_controller.update_shift_power(delta, is_power_sprinting)
	_handle_movement(delta)
	_handle_jump(delta)

	if gravity_controller.gravity_state == GravityController.GravityState.SHIFTING:
		gravity_controller.update_shift(delta)
	elif gravity_controller.gravity_state == GravityController.GravityState.LEVITATING:
		gravity_controller.update_levitating(delta)
	elif gravity_controller.gravity_state == GravityController.GravityState.WALL:
		gravity_controller.update_wall_follow(delta)

	if gravity_controller.gravity_state != GravityController.GravityState.GROUNDED:
		_update_orientation(delta)

	# Every contributor has had its say -- collapse the frame's total
	# acceleration into velocity, once, here.
	_integrate_velocity(delta)

	move_and_slide()

	gravity_controller.detect_wall()

	spring_arm.update_pivot_position(delta)

	telekinesis_controller.update(delta)

	if Particle_Controller:
		Particle_Controller.update(delta)

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
		run_timer = 0.0
		is_running = false
		is_power_sprinting = false
		jump_buffer_timer = 0.0
		return

	if Input.is_action_pressed("Run") and move_input.length_squared() > 0.0:
		run_timer += delta

		if run_timer >= RUN_THRESHOLD:
			is_running = true
	else:
		run_timer = 0.0
		is_running = false

	is_power_sprinting = is_running \
		and Input.is_action_pressed("PowerSprint") \
		and gravity_controller.gravity_state == GravityController.GravityState.GROUNDED \
		and gravity_controller.shift_power > 0.0

	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer

	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta


# ============================================================
# GRAVITY
# ============================================================
func _apply_gravity(delta):

	if is_on_floor():
		var planar_velocity: Vector3 = velocity.slide(gravity_controller.gravity_direction)

		# Arm the brake only on the frame we actually touch down, and
		# only if we arrived faster than the limit. Running this check
		# every grounded frame instead would cap ALL ground movement at
		# max_landing_speed, which silently cancels power sprinting.
		if not was_grounded_last_frame and planar_velocity.length() > max_landing_speed:
			landing_brake_timer = landing_brake_time

		if landing_brake_timer > 0.0:
			landing_brake_timer -= delta

			if planar_velocity.length() > max_landing_speed:
				var capped: Vector3 = planar_velocity.normalized() * max_landing_speed
				add_acceleration(
					acceleration_toward(planar_velocity, capped, landing_brake_acceleration, delta)
				)

		coyote_timer = coyote_time
		jumps_used = 0
	else:
		coyote_timer -= delta
		landing_brake_timer = 0.0

	was_grounded_last_frame = is_on_floor()

	gravity_controller.apply_gravity(delta)

# ============================================================
# JUMP
# ============================================================
func _handle_jump(_delta: float) -> void:

	if jump_buffer_timer > 0.0:

		if coyote_timer > 0.0:
			add_impulse(-gravity_controller.gravity_direction * jump_velocity)
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			jumps_used = 1

		elif jumps_used < max_jumps and gravity_controller.drain_power(air_jump_power_cost):
			var up: Vector3 = -gravity_controller.gravity_direction

			# Cancel whatever vertical momentum is already there and
			# replace it with a fresh jump, as one combined impulse --
			# an air jump should feel identical whether you're rising
			# or falling when you press it.
			add_impulse(-velocity.project(up) + up * jump_velocity)

			jump_buffer_timer = 0.0

			if animation_controller:
				match jumps_used:
					1:
						animation_controller.play_double_jump()
					2:
						animation_controller.play_triple_jump()

			jumps_used += 1

# ============================================================
# ORIENTATION  (physics body -- drives movement-direction math)
# ============================================================
func _update_orientation(delta: float) -> void:

	var up := -gravity_controller.gravity_direction

	var forward: Vector3 = -aim_pivot.global_basis.z
	forward = forward.slide(up)

	if forward.length_squared() < 0.001:
		return

	forward = forward.normalized()

	var target_basis := Basis.looking_at(forward, up)

	# Pivots about the body's centre rather than its origin/feet, so
	# reorienting never sweeps the capsule through nearby geometry.
	set_basis_preserving_center(Basis(
		global_basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			delta * 5.0
		)
	))


func _update_model_orientation(delta: float) -> void:

	var up := -gravity_controller.gravity_direction

	var current_forward: Vector3 = -model_yaw_basis.z
	var realigned_forward: Vector3 = current_forward.slide(up)
	if realigned_forward.length_squared() < 0.0001:
		realigned_forward = model_yaw_basis.x.slide(up)
	if realigned_forward.length_squared() < 0.0001:
		return
	realigned_forward = realigned_forward.normalized()

	var realigned_basis := Basis.looking_at(realigned_forward, up)
	model_yaw_basis = Basis(
		model_yaw_basis.get_rotation_quaternion().slerp(
			realigned_basis.get_rotation_quaternion(),
			rotation_speed * delta
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
	var spd := lerpf(lerpf(walk_speed, run_speed, run_blend), power_sprint_speed, power_blend)

	return {
		"target_velocity": dir * spd,
		"target_forward": dir
	}


# ============================================================
# MOVEMENT
# ============================================================
func _handle_movement(delta: float) -> void:

	if move_input.length_squared() > 0.0:
		var run_target: float = 1.0 if is_running else 0.0
		var run_blend_speed: float = 1.0 - exp(-delta / max(run_ramp_time, 0.001))
		run_blend = move_toward(run_blend, run_target, run_blend_speed)

		var power_target: float = 1.0 if is_power_sprinting else 0.0
		var power_blend_speed: float = 1.0 - exp(-delta / max(power_sprint_ramp_time, 0.001))
		power_blend = move_toward(power_blend, power_target, power_blend_speed)
	else:
		run_blend = 0.0
		power_blend = 0.0

	var target := _get_target_motion()
	var target_velocity: Vector3 = target["target_velocity"]

	var air_control := 0.45 if !is_on_floor() else 1.0
	var is_moving_input: bool = move_input.length_squared() > 0.0

	# Both sides projected onto the gravity plane, so the movement
	# acceleration only ever acts horizontally and never fights gravity
	# or a jump along the up axis.
	var current_planar_velocity: Vector3 = velocity.slide(gravity_controller.gravity_direction)
	var target_planar_velocity: Vector3 = target_velocity.slide(gravity_controller.gravity_direction)

	var max_accel: float = (move_acceleration if is_moving_input else move_deceleration) * air_control
	max_accel *= _get_sprint_grip_multiplier(is_moving_input)

	add_acceleration(
		acceleration_toward(current_planar_velocity, target_planar_velocity, max_accel, delta)
	)

	# Runs every frame, regardless of move_input.
	_update_model_orientation(delta)

	if is_moving_input:
		move_direction = target["target_forward"]
		current_speed = lerpf(lerpf(walk_speed, run_speed, run_blend), power_sprint_speed, power_blend)

		var up := -gravity_controller.gravity_direction
		var target_forward := move_direction.slide(up).normalized()

		if target_forward.length_squared() > 0.001:
			var target_basis := Basis.looking_at(target_forward, up)
			model_yaw_basis = Basis(
				model_yaw_basis
				.get_rotation_quaternion()
				.slerp(target_basis.get_rotation_quaternion(), rotation_speed * delta)
			)

	_update_turn_rate(delta)
	_apply_lean(delta)


## Extra grip blended in as the power sprint engages. Shared by
## _handle_movement and _predict_trajectory so the prediction can't
## drift out of sync with what the movement code actually does.
func _get_sprint_grip_multiplier(is_moving_input: bool) -> float:
	var target_multiplier: float = (
		power_sprint_acceleration_multiplier
		if is_moving_input
		else power_sprint_deceleration_multiplier
	)
	return lerpf(1.0, target_multiplier, power_blend)


func _update_turn_rate(delta: float) -> void:
	var up := -gravity_controller.gravity_direction
	var forward := (-model_yaw_basis.z).slide(up).normalized()

	if prev_model_forward.length_squared() > 0.0001 and forward.length_squared() > 0.0001:
		var cross := prev_model_forward.cross(forward)
		var signed_angle := atan2(cross.dot(up), prev_model_forward.dot(forward))
		var instant_rate: float = signed_angle / max(delta, 0.0001)
		turn_rate = lerp(turn_rate, instant_rate, 1.0 - exp(-10.0 * delta))

	prev_model_forward = forward

func _apply_lean(delta: float) -> void:
	var target_lean := 0.0

	# Normalized against TOP speed (sprint), not run_speed -- against
	# run_speed this saturated at 1.0 the moment you started running,
	# so running and sprinting leaned identically and the extra speed
	# read as nothing.
	var top_speed: float = maxf(maxf(power_sprint_speed, run_speed), 0.001)
	var speed_fraction: float = clampf(get_planar_speed() / top_speed, 0.0, 1.0)
	var shaped_fraction: float = pow(speed_fraction, max(lean_speed_curve_power, 0.001))

	# Faster travel both reaches the lean sooner AND raises the ceiling
	# on how far it can bank.
	var max_angle: float = deg_to_rad(lean_max_angle_deg) * lerpf(1.0, lean_high_speed_multiplier, shaped_fraction)

	if is_on_floor():
		var normalized_turn := clampf(turn_rate / lean_turn_rate_reference, -1.0, 1.0)
		target_lean = normalized_turn * max_angle * shaped_fraction

	var max_step := max_angle * lean_smoothing_speed * delta
	current_lean = move_toward(current_lean, target_lean, max_step)

	character_model.global_basis = model_yaw_basis.rotated(model_yaw_basis.z, current_lean)

func _predict_trajectory(_delta: float) -> void:
	var target := _get_target_motion()
	var target_velocity: Vector3 = target["target_velocity"]
	var target_forward: Vector3 = target["target_forward"]

	var gravity_up := -gravity_controller.gravity_direction
	var air_control := 0.45 if !is_on_floor() else 1.0
	var is_moving_input: bool = move_input.length_squared() > 0.0

	var sim_velocity: Vector3 = velocity.slide(gravity_controller.gravity_direction)
	var sim_target: Vector3 = target_velocity.slide(gravity_controller.gravity_direction)
	var sim_forward: Vector3 = (-character_model.global_basis.z).slide(gravity_up).normalized()
	var start_forward := sim_forward

	var max_accel: float = (move_acceleration if is_moving_input else move_deceleration) * air_control
	max_accel *= _get_sprint_grip_multiplier(is_moving_input)

	var safe_substep: float = max(prediction_substep, 0.005)   # never 0, never near-0
	var steps: int = int(ceil(prediction_horizon / safe_substep))
	var actual_step: float = prediction_horizon / float(steps)

	for i in steps:
		# Mirrors _handle_movement's acceleration model exactly, so
		# predicted_speed stays consistent with what actually happens
		# (it feeds the animation blend).
		var accel: Vector3 = acceleration_toward(sim_velocity, sim_target, max_accel, actual_step)
		sim_velocity += accel * actual_step

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


## Actual current speed across the ground plane, with motion along the
## gravity axis (falling, jumping) excluded. This is what locomotion
## animations should blend on -- it's what the feet are really doing.
func get_planar_speed() -> float:
	return velocity.slide(gravity_controller.gravity_direction).length()


func force_idle() -> void:
	# Intentional hard stop -- this is a "reset the character" call
	# (respawn/cutscene), not continuous motion.
	hard_stop()
	move_input = Vector2.ZERO
	run_timer = 0.0
	is_running = false

	if Particle_Controller:
		Particle_Controller.clear()

	if animation_controller:
		animation_controller.force_idle()


func stop_horizontal_velocity() -> void:
	# Intentional hard stop on the planar axes only, preserving motion
	# along gravity. Kept as an explicit, separate call rather than
	# something the movement code does implicitly.
	velocity -= velocity.slide(gravity_controller.gravity_direction)


func launch(direction: Vector3, force: float) -> void:
	add_impulse(direction.normalized() * force)


func set_running(enabled: bool) -> void:
	is_running = enabled
	if !enabled:
		run_timer = 0.0
