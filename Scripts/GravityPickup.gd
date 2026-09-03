extends Area3D
class_name GravityPickup

## Amount of shift power to restore. Leave at -1 to fully refill the meter.
@export var refill_amount: float = -1.0

## Optional: play a sound/particle effect before freeing. Assign an
## AnimationPlayer, GPUParticles3D, or AudioStreamPlayer3D child if you want
## a pickup effect -- left null is fine, the pickup will just disappear.
@export var pickup_effect: Node = null

## If true, waits for pickup_effect (if it's an AudioStreamPlayer3D) to
## finish before freeing the object, so the sound isn't cut off.
@export var wait_for_effect: bool = false

var _collected := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	print("Body entered: ", body.name)
	if _collected:
		return

	var gravity_controller: GravityController = body.get_node_or_null("GravityController")
	print("Found controller: ", gravity_controller)
	if not gravity_controller:
		return
		
	_collected = true
	gravity_controller.refill_shift_power(refill_amount)

	_play_effect_and_free()


func _play_effect_and_free() -> void:
	set_deferred("monitoring", false)

	if pickup_effect is AudioStreamPlayer3D and wait_for_effect:
		# Detach the sound so it can finish playing after the pickup body is freed.
		var sound: AudioStreamPlayer3D = pickup_effect
		remove_child(sound)
		get_tree().current_scene.add_child(sound)
		sound.global_position = global_position
		sound.play()
		sound.finished.connect(sound.queue_free)
	elif pickup_effect is GPUParticles3D:
		pickup_effect.emitting = true
	elif pickup_effect is AnimationPlayer:
		pickup_effect.play("pickup")

	queue_free()
