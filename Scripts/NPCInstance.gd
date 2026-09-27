extends CharacterBody3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
@export var animation_player_path: NodePath
var animation_player: AnimationPlayer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var brain: NPCBrain 

# ============================================================
# DEATH
# ============================================================
## Drag in the particle node already sitting on this NPC (a
## GPUParticles3D or CPUParticles3D child) -- it's triggered in place,
## not instanced, so position it under the NPC wherever you want the
## effect to originate (e.g. at the head).
@export var death_particles: Node

## Name of the animation to play on death. If the AnimationPlayer
## doesn't have it, the NPC still stops and is removed after
## death_fallback_delay instead of hanging forever.
@export var death_animation_name: String = "Death"

## Used only when death_animation_name isn't found on the
## AnimationPlayer -- how long to wait (with particles playing) before
## removing the NPC.
@export var death_fallback_delay: float = 1.5

var is_dying: bool = false

func set_brain(new_brain: NPCBrain):
	brain = new_brain

func _ready():
	if animation_player_path:
		animation_player = get_node(animation_player_path)
		play_animation("Idle")
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 1.0

func apply_velocity(new_velocity: Vector3):
	velocity.x = new_velocity.x
	velocity.z = new_velocity.z

func update_rotation_target(target_pos: Vector3):
	if (target_pos - global_position).length_squared() > 0.01:
		look_at(target_pos, Vector3.UP)

func play_animation(animation_name: String):
	if animation_player and animation_player.has_animation(animation_name):
		if animation_player.current_animation != animation_name:
			animation_player.play(animation_name)
			if animation_name == "Jump" and not animation_player.animation_finished.is_connected(_on_jump_animation_finished):
				animation_player.animation_finished.connect(_on_jump_animation_finished)

func _on_jump_animation_finished(anim_name: String):
	if anim_name == "Jump" and brain and brain.npc_states.has(self):
		brain.npc_states[self].is_jumping = false
		if brain.npc_states[self].waiting:
			play_animation("Idle")

func _physics_process(delta: float):
	if is_dying or not brain or not brain.npc_states.has(self):
		return

	# Apply gravity
	if not is_on_floor() and not brain.npc_states[self].is_jumping:
		velocity.y -= gravity * delta

	var was_on_floor = is_on_floor()
	move_and_slide()
	
	# Floor snapping
	if was_on_floor and not is_on_floor() and velocity.y <= 0:
		var snap = Vector3.DOWN * 0.2
		var snap_result = move_and_collide(snap, true)
		if snap_result:
			global_position = snap_result.get_position()

## Called by CombatController when this NPC's head hitbox is popped.
## Unregisters from the brain FIRST -- otherwise NPCBrain._physics_process
## keeps iterating over this instance next frame and throws
## "previously freed instance" errors once the NPC is actually removed.
## Freezes movement, plays the death animation and particle effect, then
## removes the NPC once the animation (or fallback delay) has played out.
func explode_head() -> void:
	if is_dying:
		return
	is_dying = true

	print("Head exploded: ", name)

	# Stop moving immediately -- is_dying already blocks _physics_process
	# from running move_and_slide again, this just clears any velocity
	# that was already in flight this frame.
	velocity = Vector3.ZERO

	if brain:
		brain.npcs.erase(self)
		brain.npc_states.erase(self)
		remove_from_group("npcs")

	if death_particles and death_particles.has_method("set"):
		if "emitting" in death_particles:
			death_particles.emitting = true

	var wait_time: float = death_fallback_delay

	if animation_player and animation_player.has_animation(death_animation_name):
		animation_player.play(death_animation_name)
		wait_time = animation_player.get_animation(death_animation_name).length

	await get_tree().create_timer(wait_time).timeout

	queue_free()
