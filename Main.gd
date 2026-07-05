extends Node

@export var location_offset := Vector3(0, 1.4, 0)
@export var sensitivity := 0.003

var pitch := 0.0
# Called when the node enters the scene tree for the first time.
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	$Camera_origin.global_position = $Player.global_position + location_offset

func _input(event):
	if event is InputEventMouseMotion:
		# Rotate left/right
		$Camera_origin.rotate_y(-event.relative.x * sensitivity)
		$Player.rotate_y(-event.relative.x * sensitivity)
		#$Camera_origin.rotate_x(-event.relative.y * sensitivity)
		
		pitch -= event.relative.y * sensitivity
		pitch = clamp(pitch, deg_to_rad(-80), deg_to_rad(80))
		$Camera_origin.rotation.x = pitch
		
