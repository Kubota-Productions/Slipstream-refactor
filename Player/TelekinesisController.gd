extends Node
class_name TelekinesisController

# ============================================================
# REFERENCES
# ============================================================
var player: CharacterBody3D
var camera: Camera3D

## Offset from the camera, in camera-local space (x = right, y = up,
## z = forward-distance). This is what pins the held object to a fixed
## spot on screen -- e.g. top-right -- instead of it swinging around
## as the character's body rotates. Deliberately NOT a scene node: a
## Marker3D parented under the character model would move with the
## character's rotation instead of the camera's, which is exactly the
## bug this replaces (object drifting in front of the camera / seeming
## to orbit the player when they turn).
@export_group("Hold Position")
@export var hold_offset: Vector3 = Vector3(0.6, 0.35, 1.4)

# ============================================================
# TARGETING
# ============================================================
@export_group("Targeting")
@export var reach: float = 8.0
## RigidBody3D nodes must be in this group to be grabbable.
@export var pickup_group: String = "telekinesis_target"

# ============================================================
# HOLD BEHAVIOR
# ============================================================
@export_group("Hold")
## How quickly a newly grabbed object closes the distance to the hold point.
@export var pull_in_time: float = 0.4
## How tightly it tracks the hold point once it has arrived.
@export var hold_smoothing_time: float = 0.08
## Velocity cap while being pulled in/held -- without this, a distant
## object's first-frame velocity would be huge (distance / delta) and
## it would snap in instantly instead of visibly accelerating toward you.
@export var max_hold_speed: float = 25.0
## If something blocks the object more than this far from the hold
## point once it has already arrived, drop it rather than fighting
## geometry indefinitely.
@export var hold_break_distance: float = 3.0
## How long after grabbing to hard-lock rotation to exactly whatever it
## was at pickup, so collision response during the pull-in/arc can't
## make it visibly wobble. After this, rotation eases into a slow
## constant spin (see hold_spin_speed_deg) instead of staying rigid.
@export var rotation_freeze_time: float = 0.4
## Rotation speed (degrees/sec, around the current "up" axis) it eases
## into once the freeze window above ends.
@export var hold_spin_speed_deg: float = 15.0

# ============================================================
# ARC (pull-in path)
# ============================================================
@export_group("Arc")
## How high the pull-in path bows upward through its midpoint. Zero
## disables the arc entirely (straight-line pull-in).
@export var arc_height: float = 1.5

# ============================================================
# IDLE BOB (once parked at the hold point)
# ============================================================
@export_group("Idle Bob")
## Fades in continuously as the object closes to within this distance
## of the hold point, instead of switching on abruptly once "arrived."
@export var bob_fade_distance: float = 1.0
@export var bob_amplitude: float = 0.05
@export var bob_frequency: float = 1.5  ## In Hz (full cycles per second).

# ============================================================
# LAUNCH
# ============================================================
@export_group("Launch")
@export var launch_speed: float = 30.0

var held_object: RigidBody3D = null
var held_object_original_gravity_scale: float = 1.0
var is_pulling_in: bool = false
var held_elapsed: float = 0.0  ## Time since grab -- drives the arc, the rotation freeze, and the idle bob's phase.


func setup(owner: CharacterBody3D, cam: Camera3D) -> void:
	player = owner
	camera = cam


## Called from Player._unhandled_input -- input handling stays centralized
## there, same as GravityShift/CancelShift, rather than each component
## listening for its own input independently.
func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("Telekinesis"):
		if held_object:
			_launch_held_object()
		else:
			_try_grab()



func _try_grab() -> void:
	if held_object or not camera or not player:
		return

	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_transform.basis.z * reach)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]

	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return

	var body := hit.collider as RigidBody3D
	if not body or not body.is_in_group(pickup_group):
		return

	held_object = body
	held_object_original_gravity_scale = body.gravity_scale
	body.gravity_scale = 0.0
	body.angular_velocity = Vector3.ZERO
	is_pulling_in = true
	held_elapsed = 0.0


## Called from Player._physics_process, after move_and_slide() so the
## hold point (if it moves/rotates with the character) reflects this
## frame's final resolved position.
func update(delta: float) -> void:
	if not held_object:
		return

	if not is_instance_valid(held_object) or not camera:
		held_object = null
		return

	held_elapsed += delta

	var true_target: Vector3 = (
		camera.global_position
		+ camera.global_transform.basis.x * hold_offset.x
		+ camera.global_transform.basis.y * hold_offset.y
		- camera.global_transform.basis.z * hold_offset.z
	)

	var true_distance: float = (true_target - held_object.global_position).length()

	if is_pulling_in and true_distance < 0.15:
		is_pulling_in = false
	elif not is_pulling_in and true_distance > hold_break_distance:
		_drop_held_object()
		return

	var up: Vector3 = player.up_direction
	var right: Vector3 = player.global_basis.x
	var forward: Vector3 = -player.global_basis.z

	var steering_target: Vector3 = true_target

	if is_pulling_in:
		# Bow the path upward through the middle of the trip instead of
		# pulling in a straight line. sin(PI*t) is 0 at both t=0 and
		# t=1, so this blends seamlessly back onto the true target
		# right as it arrives -- no snap at the end of the arc.
		var t: float = clamp(held_elapsed / max(pull_in_time, 0.001), 0.0, 1.0)
		var arc_offset: float = sin(PI * t) * arc_height
		steering_target += up * arc_offset

	# Idle bob: fades in continuously as the object nears the hold
	# point (by true_distance, not by the is_pulling_in flag flipping),
	# and layers a few mismatched frequencies/axes instead of one pure
	# vertical sine so it doesn't read as a single obvious metronome.
	var bob_fade_raw: float = clamp(1.0 - (true_distance / max(bob_fade_distance, 0.001)), 0.0, 1.0)
	var bob_fade: float = bob_fade_raw * bob_fade_raw * (3.0 - 2.0 * bob_fade_raw)  # smoothstep

	if bob_fade > 0.0:
		var bob_vertical: float = sin(held_elapsed * bob_frequency * TAU) * bob_amplitude
		var bob_horizontal: float = sin(held_elapsed * bob_frequency * 0.63 * TAU + 1.3) * bob_amplitude * 0.4
		var bob_depth: float = sin(held_elapsed * bob_frequency * 0.47 * TAU + 2.7) * bob_amplitude * 0.3

		steering_target += (up * bob_vertical + right * bob_horizontal + forward * bob_depth) * bob_fade

	var to_target: Vector3 = steering_target - held_object.global_position
	var smoothing_time: float = pull_in_time if is_pulling_in else hold_smoothing_time
	var weight: float = 1.0 - exp(-delta / max(smoothing_time, 0.001))

	var desired_velocity: Vector3 = to_target * weight / max(delta, 0.0001)
	if desired_velocity.length() > max_hold_speed:
		desired_velocity = desired_velocity.normalized() * max_hold_speed

	held_object.linear_velocity = desired_velocity

	if held_elapsed < rotation_freeze_time:
		# Hard-locked to exactly whatever rotation it had at pickup.
		held_object.angular_velocity = Vector3.ZERO
	else:
		# Eases from frozen into a slow constant spin, rather than
		# damping down to a stop.
		var target_angular_velocity: Vector3 = up * deg_to_rad(hold_spin_speed_deg)
		held_object.angular_velocity = held_object.angular_velocity.lerp(target_angular_velocity, weight)


func _launch_held_object() -> void:
	if not held_object:
		return

	if is_instance_valid(held_object):
		var direction: Vector3 = -camera.global_transform.basis.z
		held_object.gravity_scale = held_object_original_gravity_scale
		held_object.linear_velocity = direction.normalized() * launch_speed

	held_object = null
	is_pulling_in = false


func _drop_held_object() -> void:
	if is_instance_valid(held_object):
		held_object.gravity_scale = held_object_original_gravity_scale

	held_object = null
	is_pulling_in = false
