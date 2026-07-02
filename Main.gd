extends Node

@export var location_offset := Vector3(0, 2.4, -1.8)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	$Camera.global_position = $Player.global_position + location_offset
	pass
