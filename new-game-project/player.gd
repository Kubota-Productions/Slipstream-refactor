extends CharacterBody3D



@onready var pivot = $"Camera origin"
@export var sesitivity = 0.5

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var gravitational_diraction : Vector3 = Vector3.DOWN

enum grav_states {
	NORMAL,
	MODIFIED,
	FLOATING,
	LANDING #for changing 
}
var current_grav_state : grav_states

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sesitivity))
		pivot.rotate_x(deg_to_rad(-event.relative.y * sesitivity))
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-90), deg_to_rad(45))
	if Input.action_press("swich grav direction"):
		gravitational_diraction = $"Camera origin/SpringArm3D/Camera3D".global_rotation #idk how to turn rotation to vector in simple way
		

func _physics_process(delta):
	
	if current_grav_state < 2 and not is_on_floor():
		velocity -= gravitational_diraction * gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
