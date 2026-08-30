extends Control

@export var Cam_controller: Node
@export var player_cam: Camera3D
@export var boresight: Control
@export var mouse_pos: Control
@export var gravity_controller: GravityController
@export var shift_power_bar: TextureProgressBar

# ============================================================
# LOOK AT  (drives a LookAtModifier3D on the character's head/spine)
# ============================================================
@export_group("Look At")
@export var look_at_target: Node3D  # a Marker3D that LookAtModifier3D's Target Node points at

#hud flash
@export var flash_threshold: float = 0.3
@export var flash_speed_min: float = 3.0
@export var flash_speed_max: float = 8.0
@export var flash_color: Color = Color(1.0, 0.2, 0.2)

var flash_time: float = 0.0
var base_bar_color: Color = Color.WHITE


func _ready() -> void:
	if shift_power_bar:
		base_bar_color = shift_power_bar.modulate


func _process(delta: float) -> void:
	update_graphics(delta)
	if Cam_controller == null or player_cam == null:
		return


func update_graphics(delta: float) -> void:
	if Cam_controller == null or player_cam == null:
		return

	# Boresight world position -- shared by the 2D reticle and the 3D look-at target.
	var boresight_world_pos: Vector3 = Cam_controller.get_boresight_pos()

	# Boresight (2D reticle)
	if boresight:
		var boresight_screen_pos: Vector2 = player_cam.unproject_position(boresight_world_pos)
		boresight.position = boresight_screen_pos - boresight.size / 2

	# Drive the LookAtModifier3D's target to the same point in world space.
	if look_at_target:
		look_at_target.global_position = boresight_world_pos

	# Mouse Aim Position
	if mouse_pos:
		var mouse_aim_world_pos: Vector3 = Cam_controller.get_mouse_aim_pos()
		var mouse_pos_screen_pos: Vector2 = player_cam.unproject_position(mouse_aim_world_pos)
		mouse_pos.position = mouse_pos_screen_pos - mouse_pos.size / 2

	# Shift Power Bar
	if shift_power_bar and gravity_controller:
		shift_power_bar.max_value = gravity_controller.max_shift_power
		shift_power_bar.value = gravity_controller.shift_power

		var ratio: float = gravity_controller.shift_power / gravity_controller.max_shift_power

		if ratio <= flash_threshold and ratio > 0.0:
			var urgency: float = 1.0 - (ratio / flash_threshold)
			var speed: float = lerp(flash_speed_min, flash_speed_max, urgency)

			flash_time += delta * speed
			var pulse: float = (sin(flash_time * TAU) + 1.0) * 0.5

			shift_power_bar.modulate = base_bar_color.lerp(flash_color, pulse)
		else:
			flash_time = 0.0
			shift_power_bar.modulate = base_bar_color
