extends SpringArm3D

@export var mouse_sensitivity: float = 0.005
@export var aim_pivot: Node3D

var yaw_input: float = 0.0
var pitch_input: float = 0.0
var camera_moved = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity
		
func _physics_process(delta):

	rotation.x += pitch_input
	rotation.x = clamp(
		rotation.x,
		deg_to_rad(-80),
		deg_to_rad(60)
	)

	rotation.y += yaw_input

	if aim_pivot:
		aim_pivot.rotation = rotation

	yaw_input = 0
	pitch_input = 0
