extends Node3D

@export var location_offset := Vector3(0, 2.4, -1.8)

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	$Camera.global_position = $Player.global_position + location_offset
