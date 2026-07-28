extends Node
class_name GravityController

signal gravity_changed(direction: Vector3)
signal wall_attached(normal: Vector3)

enum GravityState {
	GROUNDED,
	LEVITATING,
	SHIFTING,
	WALL
}

@export var shift_distance := 250.0
@export var shift_start_speed := 10.0
@export var shift_acceleration := 45.0
@export var max_shift_speed := 35.0
@export var wall_snap_distance := 0.05

var gravity_state := GravityState.GROUNDED
var gravity_direction := Vector3.DOWN

var shift_speed := 0.0

var player: CharacterBody3D
var camera: Camera3D


func setup(owner: CharacterBody3D, cam: Camera3D):
	player = owner
	camera = cam


func enter_levitating():

	player.velocity = Vector3.ZERO

	gravity_state = GravityState.LEVITATING


func perform_shift():

	gravity_direction = calculate_shift_direction()

	shift_speed = shift_start_speed

	gravity_state = GravityState.SHIFTING

	gravity_changed.emit(gravity_direction)


func update_shift(delta):

	if gravity_state != GravityState.SHIFTING:
		return

	shift_speed = min(
		shift_speed + shift_acceleration * delta,
		max_shift_speed
	)

	player.velocity = gravity_direction * shift_speed


func calculate_shift_direction() -> Vector3:

	var from = camera.global_position
	var to = from + (-camera.global_basis.z * shift_distance)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]

	var hit = player.get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		return (hit.position - player.global_position).normalized()

	return (to - player.global_position).normalized()


func check_wall():

	if gravity_state != GravityState.SHIFTING:
		return

	for i in player.get_slide_collision_count():

		var collision = player.get_slide_collision(i)

		if collision.get_normal().dot(-gravity_direction) > 0.8:

			_attach_to_wall(collision)

			return


func _attach_to_wall(collision: KinematicCollision3D):

	var normal = collision.get_normal()

	var capsule := player.get_node("CollisionShape3D").shape as CapsuleShape3D

	player.velocity = Vector3.ZERO

	player.global_position = (
		collision.get_position()
		+ normal * (capsule.radius + wall_snap_distance)
	)

	gravity_direction = -normal

	gravity_state = GravityState.WALL

	gravity_changed.emit(gravity_direction)

	wall_attached.emit(normal)


func return_to_ground():

	gravity_direction = Vector3.DOWN

	gravity_state = GravityState.GROUNDED

	gravity_changed.emit(gravity_direction)
