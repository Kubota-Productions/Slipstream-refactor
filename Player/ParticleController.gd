extends Node
class_name ParticleController

# ============================================================
# REFERENCES
# ============================================================
var player: Player

## GPUParticles3D emitting the dust. Parent it at the character's feet
## (a child of the Player, so it inherits the gravity-aligned rotation
## and keeps kicking dust "downward" correctly while wall-walking).
@export var particles: GPUParticles3D

# ============================================================
# SPEED RESPONSE
# ============================================================
@export_group("Speed Response")
## Below this planar speed, no dust at all -- walking shouldn't kick
## anything up.
@export var min_speed: float = 3.0
## Speed at which the effect is at full strength. Defaults are aimed
## at run_speed (5.0) starting it and power_sprint_speed (9.0)
## maxing it out.
@export var max_speed: float = 9.0
## Shapes the ramp between min_speed and max_speed. Above 1.0 keeps
## dust sparse until you're genuinely moving; below 1.0 makes it come
## on strong early.
@export var response_curve_power: float = 1.4
## How quickly the intensity follows speed changes. Prevents the
## emission popping on and off over small speed jitters.
@export var intensity_smoothing_time: float = 0.12

# ============================================================
# SCALING
# ============================================================
@export_group("Scaling")
## Fraction of the particle system's configured amount emitted at
## minimum intensity vs. full intensity.
@export var min_amount_ratio: float = 0.15
@export var max_amount_ratio: float = 1.0
## Particle size multiplier across the intensity range. Applied to a
## duplicated ProcessMaterial, so it won't leak into other scenes
## sharing the same material resource.
@export var min_scale_multiplier: float = 0.6
@export var max_scale_multiplier: float = 1.6
## Initial velocity multiplier -- faster running throws dust further,
## not just more of it. Driven directly by actual planar speed (see
## Velocity Response below), not by current_intensity -- so it isn't
## forced to share the same curve/smoothing as amount and scale.
@export var min_velocity_multiplier: float = 0.6
@export var max_velocity_multiplier: float = 1.8

# ============================================================
# VELOCITY RESPONSE
# Initial Velocity gets its own speed tracking and curve, separate
# from current_intensity (which still drives amount_ratio and particle
# scale). Sharing one curve for everything means velocity can only
# ever change as fast/in the same shape as emission amount does --
# splitting it out lets "how hard dust gets thrown" be tuned and
# smoothed independently of "how much dust appears."
# ============================================================
@export_group("Velocity Response")
## Speed range velocity is normalized against. Independent from the
## Speed Response group's min/max_speed above -- e.g. widen this past
## max_speed if you want velocity to keep climbing even once amount/
## scale have already maxed out.
@export var velocity_min_speed: float = 3.0
@export var velocity_max_speed: float = 9.0
@export var velocity_response_curve_power: float = 1.0
## Separate smoothing from intensity_smoothing_time -- lower this for
## velocity to feel snappier/more direct than the emission amount does.
@export var velocity_smoothing_time: float = 0.08

var current_velocity_factor: float = 0.0

var current_intensity: float = 0.0

var _process_material: ParticleProcessMaterial
var _base_scale_min: float = 1.0
var _base_scale_max: float = 1.0
var _base_velocity_min: float = 0.0
var _base_velocity_max: float = 0.0


func setup(owner: Player) -> void:
	player = owner

	if not particles:
		push_warning("RunDustController: no GPUParticles3D assigned -- run dust disabled.")
		return

	# Duplicate the process material so the runtime scaling below only
	# affects this instance. Without this, writing to the material
	# would mutate the shared resource and change every other particle
	# system using it.
	var source_material := particles.process_material as ParticleProcessMaterial
	if source_material:
		_process_material = source_material.duplicate() as ParticleProcessMaterial
		particles.process_material = _process_material

		# Cache the authored values -- all runtime scaling is applied
		# as a multiplier against these rather than accumulating on
		# whatever last frame left behind.
		_base_scale_min = _process_material.scale_min
		_base_scale_max = _process_material.scale_max
		_base_velocity_min = _process_material.initial_velocity_min and _process_material.initial_velocity_max
		_base_velocity_max = _process_material.initial_velocity_max and _process_material.initial_velocity_min

	particles.emitting = false


func update(delta: float) -> void:
	if not player or not particles:
		return

	var target_intensity: float = _compute_target_intensity()

	var weight: float = 1.0 - exp(-delta / max(intensity_smoothing_time, 0.001))
	current_intensity = lerpf(current_intensity, target_intensity, weight)

	# Velocity tracks actual speed on its own timeline/curve, not
	# current_intensity -- computed every frame regardless of emission
	# state so it's never stale on the frame emission turns back on.
	var target_velocity_factor: float = _compute_velocity_factor()
	var velocity_weight: float = 1.0 - exp(-delta / max(velocity_smoothing_time, 0.001))
	current_velocity_factor = lerpf(current_velocity_factor, target_velocity_factor, velocity_weight)

	if _process_material:
		var velocity_multiplier: float = lerpf(min_velocity_multiplier, max_velocity_multiplier, current_velocity_factor)
		_process_material.initial_velocity_min = _base_velocity_min * velocity_multiplier
		_process_material.initial_velocity_max = _base_velocity_max * velocity_multiplier

	# Cut emission entirely once it's faded out, rather than leaving
	# the system running and emitting a trickle of invisible particles.
	if current_intensity <= 0.01:
		particles.emitting = false
		return

	particles.emitting = true
	particles.amount_ratio = lerpf(min_amount_ratio, max_amount_ratio, current_intensity)

	if _process_material:
		var scale_multiplier: float = lerpf(min_scale_multiplier, max_scale_multiplier, current_intensity)
		_process_material.scale_min = _base_scale_min * scale_multiplier
		_process_material.scale_max = _base_scale_max * scale_multiplier


## 0 when stationary or airborne, 1 at max_speed. Requires ground
## contact -- dust comes from scuffing a surface, so there's nothing
## to kick up mid-air, including while gravity shifting.
func _compute_target_intensity() -> float:
	if not player.is_on_floor():
		return 0.0

	var speed: float = player.get_planar_speed()

	var span: float = max(max_speed - min_speed, 0.001)
	var raw: float = clampf((speed - min_speed) / span, 0.0, 1.0)

	return pow(raw, max(response_curve_power, 0.001))


## Same idea as _compute_target_intensity but against
## velocity_min_speed/velocity_max_speed and its own curve, and
## WITHOUT requiring ground contact -- momentum carried into a jump or
## a fall should still throw dust with the right amount of force on
## whatever frame emission next turns on, rather than resetting to 0
## the instant the player leaves the floor.
func _compute_velocity_factor() -> float:
	var speed: float = player.get_planar_speed()

	var span: float = max(velocity_max_speed - velocity_min_speed, 0.001)
	var raw: float = clampf((speed - velocity_min_speed) / span, 0.0, 1.0)

	return pow(raw, max(velocity_response_curve_power, 0.001))


## Stops emission immediately -- for respawns/cutscenes where the
## character is reset rather than decelerating.
func clear() -> void:
	current_intensity = 0.0
	current_velocity_factor = 0.0
	if particles:
		particles.emitting = false
