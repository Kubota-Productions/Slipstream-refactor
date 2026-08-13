extends Node
class_name GravityController

enum GravityState {
	GROUNDED,
	LEVITATING,
	SHIFTING,
	WALL
}

var spring_arm: SpringArm3D
var ground_ray_origin: Marker3D
@export var gravity_strength := 20

@export var shift_start_speed := 8.0
@export var shift_acceleration := 15.0
@export var max_shift_speed := 35.0
@export var max_shift_power: float = 100.0
@export var shift_drain_rate: float = 40.0   # power per second while levitating/shifting/wall
@export var shift_regen_rate: float = 25.0   # power per second while grounded
var shift_power: float = 100.0
@export var shift_regen_delay_after_empty: float = 3.0
var regen_delay_timer: float = 0.0

signal shift_power_changed(current: float, max: float)

var gravity_state := GravityState.GROUNDED

var gravity_direction := Vector3.DOWN
var shift_speed := 0.0

var player : CharacterBody3D
var camera: Camera3D

func _ready():
	print(camera)

func setup(owner: CharacterBody3D, cam: Camera3D):
	player = owner
	camera = cam
	ground_ray_origin = player.get_node("GroundRayOrigin")
	spring_arm = player.get_node("SpringArm3D")
	shift_power = max_shift_power
	
func check_shift_surface():

	var origin = ground_ray_origin.global_position

	var target = origin + gravity_direction * 2.0

	var query = PhysicsRayQueryParameters3D.create(
		origin,
		target
	)

	query.exclude = [player]

	var hit = player.get_world_3d().direct_space_state.intersect_ray(query)

	return hit
	
func apply_gravity(delta):

	if gravity_state == GravityState.LEVITATING:
		return

	player.velocity += gravity_direction * gravity_strength * delta

func enter_levitating():
	if shift_power <= 0.0:
		return
	player.velocity = Vector3.ZERO
	gravity_state = GravityState.LEVITATING

func return_to_ground():
	gravity_direction = Vector3.DOWN
	player.up_direction = Vector3.UP
	gravity_state = GravityState.GROUNDED

	var forward: Vector3 = -player.global_basis.z
	forward = forward.slide(Vector3.UP)

	if forward.length_squared() > 0.001:
		forward = forward.normalized()
		player.global_basis = Basis.looking_at(forward, Vector3.UP)
	else:
		player.global_basis = Basis.IDENTITY

func calculate_shift_direction() -> Vector3:

	var from = camera.global_position
	var to = from + (-camera.global_basis.z * 250)

	var query = PhysicsRayQueryParameters3D.create(from, to)

	query.exclude = [player]

	var hit = player.get_world_3d().direct_space_state.intersect_ray(query)

	if hit:

		return (hit.position - player.global_position).normalized()

	return (to - player.global_position).normalized()
	
func begin_shift():

	gravity_direction = calculate_shift_direction()

	shift_speed = shift_start_speed

	gravity_state = GravityState.SHIFTING
	
func update_shift(delta):

	shift_speed += shift_acceleration * delta

	shift_speed = min(
		shift_speed,
		max_shift_speed
	)

	player.velocity = gravity_direction * shift_speed

func update_shift_power(delta: float) -> void:
	var draining := gravity_state == GravityState.LEVITATING \
		or gravity_state == GravityState.SHIFTING \
		or gravity_state == GravityState.WALL

	if draining:
		shift_power = max(shift_power - shift_drain_rate * delta, 0.0)
		if shift_power <= 0.0:
			regen_delay_timer = shift_regen_delay_after_empty
			return_to_ground()
	elif gravity_state == GravityState.GROUNDED:
		if regen_delay_timer > 0.0:
			regen_delay_timer -= delta
		else:
			shift_power = min(shift_power + shift_regen_rate * delta, max_shift_power)

	shift_power_changed.emit(shift_power, max_shift_power)

func detect_wall():

	if gravity_state != GravityState.SHIFTING:
		return

	var hit = check_shift_surface()

	if hit:

		attach_to_surface(hit)
			
func attach_to_surface(hit):

	var normal: Vector3 = hit.normal

	gravity_direction = -normal

	player.up_direction = normal

	player.velocity = Vector3.ZERO

	player.global_position = hit.position

	if spring_arm:
		spring_arm.rotation.y = 0.0

	gravity_state = GravityState.WALL
	

	
