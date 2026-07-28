extends Node
class_name GravityController

enum GravityState {
	GROUNDED,
	LEVITATING,
	SHIFTING,
	WALL
}

@export var gravity_strength := 9.8

@export var shift_start_speed := 8.0
@export var shift_acceleration := 30.0
@export var max_shift_speed := 35.0

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
	
func apply_gravity(delta):

	if gravity_state == GravityState.LEVITATING:
		return

	player.velocity += gravity_direction * gravity_strength * delta

func enter_levitating():

	player.velocity = Vector3.ZERO

	gravity_state = GravityState.LEVITATING

func return_to_ground():

	gravity_direction = Vector3.DOWN

	player.up_direction = Vector3.UP

	gravity_state = GravityState.GROUNDED

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
	
func detect_wall():

	if gravity_state != GravityState.SHIFTING:
		return

	for i in player.get_slide_collision_count():

		var collision = player.get_slide_collision(i)

		if collision.get_normal().dot(-gravity_direction) > 0.8:

			attach_to_wall(collision)

			return
			
func attach_to_wall(collision):

	var normal = collision.get_normal()

	gravity_direction = -normal

	player.up_direction = normal

	player.velocity = Vector3.ZERO

	gravity_state = GravityState.WALL
	
