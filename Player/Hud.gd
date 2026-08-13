extends Control

@export var Cam_controller: Node
@export var player_cam: Camera3D
@export var boresight: Control
@export var mouse_pos: Control
@export var gravity_controller: GravityController
@export var shift_power_bar: TextureProgressBar


func _process(_delta: float) -> void:
	update_graphics()
	if Cam_controller == null or player_cam == null:
		return

func update_graphics() -> void:
	if Cam_controller == null or player_cam == null:
		return

	# Boresight
	if boresight:
		var boresight_world_pos: Vector3 = Cam_controller.get_boresight_pos()
		var boresight_screen_pos: Vector2 = player_cam.unproject_position(boresight_world_pos)
		boresight.position = boresight_screen_pos - boresight.size / 2

	# Mouse Aim Position
	if mouse_pos:
		var mouse_aim_world_pos: Vector3 = Cam_controller.get_mouse_aim_pos()
		var mouse_pos_screen_pos: Vector2 = player_cam.unproject_position(mouse_aim_world_pos)
		mouse_pos.position = mouse_pos_screen_pos - mouse_pos.size / 2

	# Shift Power Bar
	if shift_power_bar and gravity_controller:
		shift_power_bar.max_value = gravity_controller.max_shift_power
		shift_power_bar.value = gravity_controller.shift_power
