extends CharacterBody3D

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var character_model: Node3D = $CharacterModel

@export var movement_states := {
	"Idle": {
		"id": 0,
		"movement_speed": 0.0,
		"acceleration": 8.0,
		"camera_fov": 70.0,
		"animation_speed": 1.0,
	},
	"Jog": {
		"id": 1,
		"movement_speed": 2.5,
		"acceleration": 8.0,
		"camera_fov": 70.0,
		"animation_speed": 1.0,
	},
	"Run": {
		"id": 2,
		"movement_speed": 5.0,
		"acceleration": 10.0,
		"camera_fov": 75.0,
		"animation_speed": 1.0,
	},
}

@export var rotation_speed: float = 8.0

var movement_direction: Vector3 = Vector3.ZERO
var move_direction: Vector3 = Vector3.ZERO

var speed: float = 0.0
var acceleration: float = 0.0
var cam_rotation: float = 0.0

# Sprint timer
var sprint_timer: float = 0.0
const SPRINT_THRESHOLD: float = 0.6

func _ready():
	#_set_movement_state(movement_states["Idle"])
	pass

func _physics_process(delta):
	pass
	# Input
	movement_direction.x = -Input.get_axis("left", "right")
	movement_direction.z = -Input.get_axis("forward", "backwards")

	# Movement state logic
	if is_movement_ongoing():
		if Input.is_action_pressed("Run"):
			sprint_timer += delta

			if sprint_timer >= SPRINT_THRESHOLD:
				_set_movement_state(movement_states["Run"])
				$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run")
			else:
				_set_movement_state(movement_states["Jog"])
				$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jog")
		else:
			sprint_timer = 0.0
			_set_movement_state(movement_states["Jog"])
			$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jog")
	else:
		sprint_timer = 0.0
		_set_movement_state(movement_states["Idle"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|idle")

	# Gravity
	if !is_on_floor():
		velocity.y -= 10.0 * delta
	else:
		velocity.y = 0.0

	# Movement
	if is_movement_ongoing():
		move_direction = movement_direction.rotated(Vector3.UP, cam_rotation)

		var target_velocity := move_direction.normalized() * speed

		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)

		# Character rotation
		var target_rotation := atan2(move_direction.x, move_direction.z) - rotation.y

		character_model.rotation.y = lerp_angle(
			character_model.rotation.y,
			target_rotation,
			rotation_speed * delta
		)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

	move_and_slide()

	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

func _set_movement_state(state: Dictionary):
	speed = state["movement_speed"]
	acceleration = state["acceleration"]

	#direct assignment (no Tween, no path resolution)
	animation_tree.set("parameters/movement_blend/blend_position", state["id"])
	animation_tree.set("parameters/movement_anim_speed/scale", state["animation_speed"])

func is_movement_ongoing() -> bool:
	return movement_direction.length() > 0.001
