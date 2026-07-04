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
	"Idle_Jump": {
		"id": 3,
		"movement_speed": 0.0,
		"acceleration": 0.0,
		"camera_fov": 75.0,
		"animation_speed": 1.0,
	},
	"Jog_Jump": {
		"id": 4,
		"movement_speed": 2.5,
		"acceleration": 8.0,
		"camera_fov": 75.0,
		"animation_speed": 1.0,
	},
	"Run_Jump": {
		"id": 5,
		"movement_speed": 5.0,
		"acceleration": 10.0,
		"camera_fov": 75.0,
		"animation_speed": 1.0,
	}
}

@export var rotation_speed: float = 8.0

var movement_direction: Vector3 = Vector3.ZERO
var move_direction: Vector3 = Vector3.ZERO

var speed: float = 0.0
var acceleration: float = 0.0
var cam_rotation: float = 0.0

# Sprint timer
var is_running = false
var run_timer: float = 0.0
const RUN_THRESHOLD: float = 0.4

# Jump timer
var is_jumping = false
var jump_timer: float = 0.0
const IDLE_JUMP_THRESHOLD: float = 1.77 #change this to your animation run idle jump timer
const RUN_JUMP_THRESHOLD: float = 0.92 #change this to your animation's run jump timer

var is_run_jumping = false
var is_jog_jumping = false
var is_idle_jumping = false
var previous_jump_case = -1

func _ready():
	#_set_movement_state(movement_states["Idle"])
	pass

func _physics_process(delta):
	
	# Input
	movement_direction.x = -Input.get_axis("left", "right")
	movement_direction.z = -Input.get_axis("forward", "backwards")
	
	# ------ UPDATE IDLE/JOG/RUN
	var movement_ongoing = is_movement_ongoing()
	var run_pressed = Input.is_action_pressed("Run")
	var jump_pressed = Input.is_action_just_pressed("Jump")
	var threshold = run_timer >= RUN_THRESHOLD
	
	#print("movement_ongoing = ", movement_ongoing, " // run_timer = ", run_timer, " // jump_timer = ", jump_timer)
	
	# --- CASE 1: NOT JUMPING
	#idle state
	if not movement_ongoing:
		if is_running:
			#set run to false
			is_running = false
			
			#set run_timer to zero
			run_timer = 0.0
		else:
			pass
		
		if is_jumping:
			if is_run_jumping and jump_timer < RUN_JUMP_THRESHOLD:
				
				#iterate the timer
				jump_timer += delta
				pass
			else:
				#set jump to false
				is_jumping = false
				
				#set jump states to false
				is_idle_jumping = false
				is_jog_jumping = false
				is_run_jumping = false
				
				#set jump timer to zero
				jump_timer = 0.0
		else:
			pass
		
		#set run timer to zero
		run_timer = 0.0
	
	#non-idle states
	if movement_ongoing:
		if not is_jumping:
			#sanity check - increment run_timer if run pressed
			if run_pressed:
				run_timer += delta
			else:
				run_timer = 0.0
				
			if is_running and run_pressed and jump_pressed and threshold:
				#case 1: player running, run pressed, jump just pressed, threshold met
				#default case to start run_jump anim
				
				is_idle_jumping = false
				is_jog_jumping = false
				is_run_jumping = true
				is_jumping = true
			elif is_running and run_pressed and jump_pressed and not threshold:
				#not handling jumps now
				pass
			elif is_running and run_pressed and not jump_pressed and threshold:
				
				#case 3: player running, run pressed, jump not just pressed, threshold met
				#default state for run loop - pass
				pass
			elif is_running and run_pressed and not jump_pressed and not threshold:
				
				#case 4: player running, run presed, jump not just pressed, threshold met
				#default state to cancel run loop - running but threshold not met
				is_running = false
				run_timer = 0.0
				pass
			elif is_running and not run_pressed and jump_pressed and threshold:
				#not handling jumps now
				pass
			elif is_running and not run_pressed and jump_pressed and not threshold:
				#not handling jumps now
				pass
			elif is_running and not run_pressed and not jump_pressed and threshold:
				
				#case 7: player running, run not pressed, jump not just pressed, threshold met
				#cancel run state -> run not pressed
				is_running = false
				run_timer = 0.0
				pass
			elif is_running and not run_pressed and not jump_pressed and not threshold:
				
				#case 8: player running, run not pressed, jump not just pressed, threshold not met
				#cancel run state -> run not pressed and threshold not met
				is_running = false
				run_timer = 0.0
				pass
			elif not is_running and run_pressed and jump_pressed and threshold:
				#not handling jumps now
				pass
			elif not is_running and run_pressed and jump_pressed and not threshold:
				#not handling jumps now
				pass
			elif not is_running and run_pressed and not jump_pressed and threshold:
				#case 11: player not running, run pressed, jump not just pressed, threshold met
				#default state to start run cycle
				
				#start run cycle
				is_running = true
				pass
			elif not is_running and run_pressed and not jump_pressed and not threshold:
				#case 12: player not running, run pressed, jump not just pressed, threshold not met
				#default state to load run cycle - pass
				pass
			elif not is_running and not run_pressed and jump_pressed and threshold:
				#not handling jumps now
				pass
			elif not is_running and not run_pressed and jump_pressed and not threshold:
				#not handling jumps now
				pass
			elif not is_running and not run_pressed and not jump_pressed and threshold:
				#case 15: player not running, run not pressed, jump not just pressed, threshold met
				#bug state: need to zero timer 
				
				#zero timer
				is_running = false
				run_timer = 0.0
				pass
			elif not is_running and not run_pressed and not jump_pressed and not threshold:
				#case 16: player not running, run not pressed, jump not just pressed, not over threshold
				#default state for jog cycle
				
				#if you are running, stop and zero the timer
				if is_running:
					is_running = false
					run_timer = 0.0
	
	# --- CASE 2: JUMPING
	#idle states
	if not movement_ongoing:
		if is_jumping:
			#sanity check -- set jump_timer back to zero if we're done jumping
			is_jumping = (is_run_jumping and jump_timer < RUN_JUMP_THRESHOLD) or (is_jog_jumping and jump_timer < IDLE_JUMP_THRESHOLD) or (is_idle_jumping and jump_timer < IDLE_JUMP_THRESHOLD)
			
			#print("is_run_jumping = ", is_run_jumping, " // is_jog_jumping = ", is_jog_jumping, " // is_idle_jumping = ", is_idle_jumping)
			#print("is_jumping = ", is_jumping)
			#check if we're still jumping
			if !is_jumping:
				#set timer to zero
				jump_timer = 0.0
				
				#reset run states
				is_idle_jumping = false
				is_jog_jumping = false
				is_run_jumping = false
			#otherwise continue
			else:
				pass
	#non-idle states
	if movement_ongoing:
		if is_jumping:
			#sanity check -- set jump_timer back to zero if we're done jumping
			is_jumping = (is_run_jumping and jump_timer < RUN_JUMP_THRESHOLD) or (is_jog_jumping and jump_timer < IDLE_JUMP_THRESHOLD) or (is_idle_jumping and jump_timer < IDLE_JUMP_THRESHOLD)
			
			#check if we're still jumping
			if !is_jumping:
				#set timer to zero
				jump_timer = 0.0
				
				#reset run states
				is_idle_jumping = false
				is_jog_jumping = false
				is_run_jumping = false
			#otherwise continue
			else:
				jump_timer += delta
				
			if is_running and run_pressed and jump_pressed and threshold:
				print("jump - case 1")
				#case 1 TTTT
				
				#case 1: player is running, run is pressed, jump just pressed, threshold met
				# -> this is the starting case for the jump animation - pass
				# -> don't do anything unless you want a double jump
				pass
			elif is_running and run_pressed and jump_pressed and not threshold:
				print("jump - case 2")
				#case 2 TTTF
				pass
			elif is_running and run_pressed and not jump_pressed and threshold:
				print("jump - case 3")
				#case 3 TTFT
				
				
				#case 3: player is running, run is pressed, jump not pressed and over threshold
				# -> this is the main case for the run jump animation - pass
				pass
			elif is_running and run_pressed and not jump_pressed and not threshold:
				print("jump - case 4")
				#case 4 TTFF
				pass
			elif is_running and not run_pressed and jump_pressed and threshold:
				print("jump - case 5")
				#case 5 TFTT
				pass
			elif is_running and not run_pressed and jump_pressed and not threshold:
				print("jump - case 6")
				#case 6 TFTF
				pass
			elif is_running and not run_pressed and not jump_pressed and threshold:
				
				print("jump - case 7")
				
				# -- CASE 7: player is running, run not pressed, jump not just pressed, over threshold T/F/F/T
				#bug state: can't run if run action not pressed 
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				run_timer = 0.0
				
				# note: this case T/F/F/T will trigger either case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 7 -- anim gets handled by 14 and 16
				previous_jump_case = 7
			elif is_running and not run_pressed and not jump_pressed and not threshold:
				print("jump - case 8")
				#case 8 TFFF
				pass
			elif not is_running and run_pressed and jump_pressed and threshold:
				print("jump - case 9")
				#case 9 FTTT 
				pass
			elif not is_running and run_pressed and jump_pressed and not threshold:
				print("jump - case 10")
				#case 10 FTTF
				pass
			elif not is_running and run_pressed and not jump_pressed and threshold:
				print("jump - case 11")
				#case 11 FTFT
				pass
			elif not is_running and run_pressed and not jump_pressed and not threshold:
				print("jump - case 12")
				#case 12 FTFF
				pass
			elif not is_running and not run_pressed and jump_pressed and threshold:
				print("jump - case 13")
				#case 13 FFTT
				pass
			elif not is_running and not run_pressed and jump_pressed and not threshold:
				print("jump - case 14")
				#case 14 FFTF
				
				# -- CASE 14: player not running, run not pressed, jump just pressed and not over threshold
				#seems like generally, this is the default state for jog_jump when the jump is pressed 
				#-> don't do anything extra unless you want double jumps
				
				# ERROR HANDLING - 
				# this case can be triggered by the following run states:
				#
				# 7:   is_running, !run_pressed, !jump_pressed,  threshold
				# ->  !is_running, !run_pressed,  jump_pressed, !threshold
				#
				#above cases - the player had run turned on, but because threshold is no longer valid
				#              but because they either let go of the run button or the threshold was
				#              no longer valid now they need to finish their run_jump animation at a slower speed
				if previous_jump_case == 7:
					if is_run_jumping:
						#don't do anything if run_jump is still running
						pass
					else:
						#otherwise reset run states (this will stop is_jumping on the next frame)
						is_idle_jumping = false
						is_jog_jumping = false
						is_run_jumping = false
						
						#reset jump case
						previous_jump_case = -1
			elif not is_running and not run_pressed and jump_pressed and not threshold:
				print("jump - case 15")
				#case 15 FFTF
				pass
			elif not is_running and not run_pressed and not jump_pressed and not threshold:
				print("jump - case 16")
				
				# -- CASE 16: player not running, run not pressed, jump not pressed and not over threshold
				#seems like the default state for jog_jump
				#-> don't do anything extra unless you want double jumps
				
				# ERROR HANDLING - 
				# this case can be triggered by the following run states:
				#
				# 7:   is_running, !run_pressed, !jump_pressed,  threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				if previous_jump_case == 7:
					if is_run_jumping:
						#don't do anything if run_jump is still running
						pass
					else:
						#otherwise reset run states (this will stop is_jumping on the next frame)
						is_idle_jumping = false
						is_jog_jumping = false
						is_run_jumping = false
						
						#and reset jump case
						previous_jump_case = -1
				# this case can also be triggered by the following jog states:
				#
				# 13:  !is_running, !run_pressed,  jump_pressed,  threshold
				# ->   !is_running, !run_pressed, !jump_pressed, !threshold
				#
				# 15:  !is_running, !run_pressed, !jump_pressed,  threshold
				#  ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				#cases 13, 15 - the player had run turned off and their threshold states is not really valid
				#               so we make sure that they complete their animations and reset anim states at
				#               the end
				if is_run_jumping and not is_jog_jumping and not is_idle_jumping:
					print("run jumping, jump_timer = ", jump_timer)
					pass
				elif is_jog_jumping and not is_run_jumping and not is_idle_jumping:
					print("jog jumping, jump_timer = ", jump_timer)
					pass
				elif is_idle_jumping and not is_run_jumping and not is_jog_jumping:
					print("idle jumping, jump_timer = ", jump_timer)
					pass
				else:
					#otherwise reset run states
					is_idle_jumping = false
					is_jog_jumping = false
					is_run_jumping = false
					
					#and reset jump case
					previous_jump_case = -1
					
					print("jump_timer = ", jump_timer)
			
			#see which case your jump falls under 
			#get_tree().paused = true
		else:
			#print("I am not jumping!")
			pass
			
	
	if !movement_ongoing and not is_jumping:
		_set_movement_state(movement_states["Idle"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|idle")
	elif movement_ongoing and not is_running and not is_jumping:
		_set_movement_state(movement_states["Jog"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jog")
	elif movement_ongoing and is_running and not is_jumping:
		_set_movement_state(movement_states["Run"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run")
	elif movement_ongoing and is_run_jumping:
		_set_movement_state(movement_states["Run_Jump"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run_jump")
		
		
	
	# Movement loop
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
		velocity.x = 0
		velocity.z = 0

	move_and_slide()

func _set_movement_state(state: Dictionary):
	speed = state["movement_speed"]
	acceleration = state["acceleration"]

	#direct assignment (no Tween, no path resolution)
	animation_tree.set("parameters/movement_blend/blend_position", state["id"])
	animation_tree.set("parameters/movement_anim_speed/scale", state["animation_speed"])

func is_movement_ongoing() -> bool:
	return movement_direction.length_squared() > 0.0025
