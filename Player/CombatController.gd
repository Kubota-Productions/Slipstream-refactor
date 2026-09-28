extends Node
class_name CombatController

# ============================================================
# REFERENCES
# ============================================================
var player: CharacterBody3D
var camera: Camera3D

# ============================================================
# TARGETING
# ============================================================
@export_group("Targeting")
@export var reach: float = 30.0

## NPC head hitboxes (Area3D or a collision shape on the head bone)
## must be in this group to be targetable.
@export var target_group: String = "npc_heads"

# ============================================================
# CHARGE / HOLD
# ============================================================
@export_group("Charge")
## How long right click must be held on a valid target before the
## head pops.
@export var charge_time: float = 0.8

## If the reticle drifts off the target for longer than this while
## charging, the charge resets instead of instantly cancelling --
## small camera wobble shouldn't punish an otherwise-good hold.
@export var target_lose_grace_time: float = 0.15

# ============================================================
# GRAVITY METER COST
# ============================================================
@export_group("Gravity Meter Cost")
## Power drained per second while actively charging a headshot --
## continuous, not a lump sum. A longer hold costs more, and running
## out of power mid-charge breaks the charge instead of the kill just
## being free past that point.
@export var power_drain_rate: float = 30.0
var gravity_controller: GravityController

# ============================================================
# CAMERA ZOOM
# ============================================================
## SpringArm3D that owns the camera's FOV/zoom profiles. Toggled via
## is_combat_aiming while charging -- see camera_spring_arm.gd's
## "Combat Aim Zoom" section for the actual FOV/spring-length values.
var spring_arm: SpringArm3D

# ============================================================
# EFFECTS
# ============================================================
@export_group("Effects")
## Optional PackedScene (explosion/gore VFX) instanced at the head
## position when it pops.
@export var explosion_effect: PackedScene = null

# ============================================================
# STATE
# ============================================================
var is_button_held: bool = false
var current_target: Node3D = null
var charge_elapsed: float = 0.0
var lose_target_timer: float = 0.0
var power_reserved: bool = false

## The NPC currently being focused (slowed down) -- owner of current_target.
var focused_npc: Node = null


func setup(owner: CharacterBody3D, cam: Camera3D) -> void:
	player = owner
	camera = cam
	gravity_controller = owner.get_node_or_null("GravityController")
	spring_arm = owner.get_node_or_null("SpringArm3D")


# ============================================================
# INPUT
# ============================================================
## Called from Player._unhandled_input.
func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("Combat"):
		if not _is_focused_view():
			print("CombatController: Combat pressed but NOT in focused view (is_ots_mode is false)")
			return
		print("CombatController: Combat pressed, focused view active -- charging")
		is_button_held = true

	elif event.is_action_released("Combat"):
		is_button_held = false
		_cancel_charge()


func _is_focused_view() -> bool:
	# Gate on the same OTS "focused view" toggled by Player.is_ots_mode
	# (see camera_spring_arm.gd's OTS Explore Mode section).
	return player and "is_ots_mode" in player and player.is_ots_mode


# ============================================================
# UPDATE
# ============================================================
## Called from Player._physics_process.
func update(delta: float) -> void:
	if not camera or not player:
		return

	if not is_button_held or not _is_focused_view():
		_set_aiming(false)
		_cancel_charge()
		return

	# Zoom is tied to holding the button in focused view, independent
	# of whether a target is currently acquired -- reads like aiming
	# down rather than snapping in only once locked on.
	_set_aiming(true)

	var target := _find_target()

	if target == null:
		if current_target != null and lose_target_timer == 0.0:
			print("CombatController: no target under reticle")
		lose_target_timer += delta
		if lose_target_timer > target_lose_grace_time:
			_cancel_charge()
		return

	lose_target_timer = 0.0

	if target != current_target:
		# Switched targets -- restart the charge on the new one.
		print("CombatController: target acquired -> ", target.name)
		_cancel_charge()
		current_target = target

	# Slow the NPC down for as long as it's held under focus.
	_set_focused_npc(_get_npc_from_head(current_target))

	# Continuous drain -- costs power for every second the charge is
	# held, right up until the kill lands. Running out mid-charge
	# breaks the charge instead of the rest of the hold being free.
	if gravity_controller and not gravity_controller.drain_power(power_drain_rate * delta):
		print("CombatController: charge broken -- ran out of shift power")
		_cancel_charge()
		return

	charge_elapsed += delta

	if charge_elapsed >= charge_time:
		_pop_head(current_target)
		_cancel_charge()


func _find_target() -> Node3D:
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_transform.basis.z * reach)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player]
	query.collide_with_areas = true

	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)

	if not hit:
		return null

	var collider: Object = hit.collider

	if collider is Node and collider.is_in_group(target_group):
		return collider

	return null


func _set_aiming(value: bool) -> void:
	if spring_arm and "is_combat_aiming" in spring_arm:
		spring_arm.is_combat_aiming = value


func _cancel_charge() -> void:
	current_target = null
	charge_elapsed = 0.0
	lose_target_timer = 0.0
	_set_focused_npc(null)


## Tells the NPC currently under focus to slow down, and releases the
## previous one. Passing null releases whoever was focused.
func _set_focused_npc(npc: Node) -> void:
	if npc == focused_npc:
		return

	if is_instance_valid(focused_npc) and focused_npc.has_method("set_focused"):
		focused_npc.set_focused(false)

	focused_npc = npc

	if is_instance_valid(focused_npc) and focused_npc.has_method("set_focused"):
		focused_npc.set_focused(true)


## Walks up from a head hitbox to the NPC that owns it.
func _get_npc_from_head(head: Node) -> Node:
	var node := head
	while node and not node.has_method("set_focused"):
		node = node.get_parent()
	return node


func _pop_head(head: Node3D) -> void:
	if not is_instance_valid(head):
		return

	print("CombatController: head exploded")

	var pop_position: Vector3 = head.global_position

	if explosion_effect:
		var fx := explosion_effect.instantiate()
		player.get_tree().current_scene.add_child(fx)
		if fx is Node3D:
			fx.global_position = pop_position

	# The head hitbox belongs to an NPC -- walk up to find it and let
	# the NPC handle its own death/ragdoll/cleanup.
	var npc := head
	while npc and not npc.has_method("explode_head"):
		npc = npc.get_parent()

	if npc and npc.has_method("explode_head"):
		npc.explode_head()
	else:
		# Fallback if no NPC owner was found: just remove the hitbox.
		head.queue_free()


func get_charge_ratio() -> float:
	return clamp(charge_elapsed / max(charge_time, 0.001), 0.0, 1.0)
