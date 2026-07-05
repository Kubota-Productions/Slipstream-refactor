extends CharacterBody3D

@export var wander_area: Vector3 = Vector3(50, 0, 50) # Size of the area to wander within
@export var speed: float = 3.0 # Speed of the NPC
@export var wait_time_range: Vector2 = Vector2(1, 5) # Range of wait times

var target_position: Vector3
var waiting: bool = false

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var wait_timer: Timer = $Timer

func _ready():
	wait_timer.connect("timeout", _on_wait_timer_timeout)
	set_random_target_position()

func _process(delta):
	if waiting:
		return

	var direction = (target_position - global_transform.origin).normalized()
	#var move_vector = direction * speed
	position += direction * speed * delta
	
	set_train_rotation(direction)
	
	#set_linear_velocity(move_vector) # Set the linear velocity directly

	if global_transform.origin.distance_to(target_position) < 1:
		print("waiting")
		wait_before_next_move()
	else:
		print("not waiting")

func set_random_target_position():
	var random_x = randf_range(-wander_area.x / 2, wander_area.x / 2)
	var random_z = randf_range(-wander_area.z / 2, wander_area.z / 2)
	target_position = global_transform.origin + Vector3(random_x, 0, random_z)
	#navigation_agent.target_position = target_position

func set_train_rotation(normalized_vector: Vector3):
	# Make sure the vector is normalized
	normalized_vector = normalized_vector.normalized()
	
	# Get the rotation needed for the train to look at the vector
	var basis = Basis().looking_at(normalized_vector)  # Corrected method name
	
	basis.y = Vector3(0, 1, 0)
	basis.z = normalized_vector
	basis.x = basis.z.cross(basis.y).normalized()
	
	var transform = Transform3D(basis, position)
	
	# Convert the rotation to Euler angles
	set_transform(transform)

func wait_before_next_move():
	waiting = true
	wait_timer.start(int( randf() ) % 5)

func _on_wait_timer_timeout():
	waiting = false
	set_random_target_position()
