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
var is_running = false
var sprint_timer: float = 0.0
const SPRINT_THRESHOLD: float = 0.2

# Jump timer
var is_jumping = false
var jump_timer: float = 0.0
const IDLE_JUMP_THRESHOLD: float = 1.77 #change this to your animation run idle jump timer
const RUN_JUMP_THRESHOLD: float = 0.92 #change this to your animation's run jump timer

var is_run_jumping = false
var is_jog_jumping = false
var is_idle_jumping = false
var prev_movement_ongoing = false
var previous_jump_case = -1
var previous_run_case = -1

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
	var threshold = sprint_timer >= SPRINT_THRESHOLD
	
	print("-----------------------")
	print("threshold = ", threshold)
	print("is_IDLE/JOG/RUN_jumping? ", is_idle_jumping, "/", is_jog_jumping, "/", is_run_jumping)
	print("movement_ongoing = ", movement_ongoing)
	print("is_running = ", is_running)
	print("is_jumping = ", is_jumping)
	print("sprint_timer = ", sprint_timer)
	
	if not movement_ongoing:
		is_running = false
		sprint_timer = 0.0
		
	if not run_pressed:
		is_running = false
		sprint_timer = 0.0
	
	# --- CASE 1 - PLAYER IS JUMPING
	'''
	#idle state
	if !movement_ongoing and is_jumping:
		if is_idle_jumping and not is_jog_jumping and not is_run_jumping:
			pass
		if is_jog_jumping and not is_idle_jumping and not is_run_jumping:
			#set run speed to jog
			is_running = false
			
			#reset sprint_timer -- there is no movement
			sprint_timer = 0.0
		if is_run_jumping and not is_idle_jumping and not is_jog_jumping:
			#set run speed to jog
			is_running = false
			
			#reset sprint_timer -- there is no movement
			sprint_timer = 0.0
	'''
	'''
	#non-idle states
	if movement_ongoing:
		if is_jumping:
			
			#sanity check -- increment jump timer
			jump_timer += delta
			
			if is_running and run_pressed and jump_pressed and threshold:
				
				# -- CASE 1: player is running, run is pressed, jump just pressed and over threshold
				#-> this is one of the default cases for the run_jump animation
				#-> don't do anything unless you want a double jump, but increment the sprint_timer
				pass
			elif is_running and run_pressed and jump_pressed and not threshold:
				
				# -- CASE 2: player is running, run is pressed, jump just pressed and not over threshold
				#bug state: can't run if sprint_timer timer not over the threshold
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				sprint_timer = 0.0
				
				#this case T/T/T/F may trigger either case 10 F/T/T/F or case 11 F/T/F/F (if run remains pressed)
				#or it may trigger case 14 F/F/T/F or case 16 F/F/F/F (if run is not pressed)
				# set previous_jump_case to 2 -- anim gets handled by 10/11 or 14/16
				previous_jump_case = 2
			elif is_running and run_pressed and not jump_pressed and threshold:
				
				# -- CASE 3: player is running, run is pressed, jump not pressed and over threshold
				#-> don't do anything, this is one of the default cases for the run jump animation
				pass
			elif is_running and run_pressed and not jump_pressed and not threshold:
				
				# -- CASE 4: player is running, run is pressed, jump not pressed, not over threshold
				#bug state: can't run if sprint_timer timer not over the threshold
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				sprint_timer = 0.0
				
				#this case T/T/F/F may trigger either case 10 F/T/T/F or case 11 F/T/F/F (if run remains pressed)
				#or it may trigger case 14 F/F/T/F or case 16 F/F/F/F (if run is not pressed)
				# set previous_jump_case to 4 -- anim gets handled by 10/11 or 14/16
				previous_jump_case = 4
			elif is_running and not run_pressed and jump_pressed and threshold:
				
				# -- CASE 5: player is running, run not pressed, jump just pressed, over threshold
				#bug state: can't run if run action not pressed
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				sprint_timer = 0.0
				
				#note: this case T/F/T/T will trigger case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 5 -- anim gets handled by 14 and 16
				previous_jump_case = 5
			elif is_running and not run_pressed and jump_pressed and not threshold:
				
				# -- CASE 6: player is running, run not pressed, jump just pressed, not over threshold
				#bug state: can't run if run action not pressed or sprint_timer not over the threshold 
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				sprint_timer = 0.0
				
				#note: this case T/F/T/F will trigger case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 6 -- anim gets handled by 14 and 16
				previous_jump_case = 6
			elif is_running and not run_pressed and not jump_pressed and threshold:
				
				# -- CASE 7: player is running, run not pressed, jump not just pressed, over threshold T/F/F/T
				#bug state: can't run if run action not pressed 
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				sprint_timer = 0.0
				
				# note: this case T/F/F/T will trigger either case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 7 -- anim gets handled by 14 and 16
				previous_jump_case = 7
			elif is_running and not run_pressed and not jump_pressed and not threshold:
				
				# -- CASE 8: player is running, run not pressed, jump not just pressed, not over threshold
				#bug state: can't run if  sprint_timer not over the threshold 
				
				#revert speed back to jog
				is_running = false
				
				#set the sprint_timer back to zero because the player is running
				sprint_timer = 0.0
				
				# note: this case T/F/F/F will trigger either case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 8 -- anim gets handled by 14 and 16
				previous_jump_case = 8
			elif not is_running and run_pressed and jump_pressed and threshold:
				
				# -- CASE 9: player not running, run pressed, jump just pressed and over threshold
				# this is not a bug state, the player has successfully loaded a run while they jump
				# and just happens to be trying to jump at the same time
				pass
			elif not is_running and run_pressed and jump_pressed and not threshold:
				
				# -- CASE 10: player not running, run pressed, jump just pressed and not over threshold
				# this is not a bug state, the player is loading a run while they jump
				# and just happens to be trying to jump at the same time
				
				# ERROR HANDLING - 
				# this case can be triggered by the following run states:
				#
				# 2:   is_running, run_pressed, !jump_pressed, !threshold
				# ->  !is_running, run_pressed,  jump_pressed, !threshold
				#
				# 4:   is_running, run_pressed, jump_pressed, !threshold
				# ->  !is_running, run_pressed, jump_pressed, !threshold
				#
				
				#cases 2,4 - the player had run turned on, but because threshold is no longer valid,
				#            now they must finish their run_jump animation at a slower speed
				if previous_jump_case == 2 or previous_jump_case == 4:
					if is_run_jumping:
						#don't do anything if run_jump is still running
						pass
					else:
						#otherwise reset run states
						is_idle_jumping = false
						is_jog_jumping = false
						is_run_jumping = false
						
						#and reset jump case
						previous_jump_case = -1
			elif not is_running and run_pressed and not jump_pressed and threshold:
				
				# -- CASE 11: player not running, run pressed, jump not just pressed and over threshold
				# this is not a bug state, the player has successfully loaded a run while they jump
				
				# ERROR HANDLING - 
				# this case can be triggered by the following run states:
				#
				# 2:   is_running, run_pressed, jump_pressed, !threshold
				# ->  !is_running, run_pressed, !jump_pressed, !threshold
				#
				# 4:   is_running, run_pressed, !jump_pressed, !threshold
				# ->  !is_running, run_pressed, !jump_pressed, !threshold
				#
				#
				#cases 2,4 - the player had run turned on, but because threshold is no longer valid,
				#            now they must finish their run_jump animation at a slower speed
				if previous_jump_case == 2 or previous_jump_case == 4:
					if is_run_jumping:
						#don't do anything if run_jump is still running
						pass
					else:
						#otherwise reset run states
						is_idle_jumping = false
						is_jog_jumping = false
						is_run_jumping = false
						
						#and reset jump case
						previous_jump_case = -1
			elif not is_running and run_pressed and not jump_pressed and not threshold:
				
				# -- CASE 12: player not running, run pressed, jump not just pressed and not over threshold
				# this is not a bug state, the player is loading a run while they jump
				pass
			elif not is_running and not run_pressed and jump_pressed and threshold:

				# -- CASE 13: player is not running, run not pressed, jump just pressed and over threshold
				#bug state: can't be over threshold and not running
				
				#set the sprint_timer back to zero because threshold was met // but run is not pressed and not running
				#and we can't sprint while jumping anyway
				sprint_timer = 0.0
				
				# note: this F/F/T/T will trigger either case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 13 -- anim will be handled by 14 or 16
				previous_jump_case = 13
			elif not is_running and not run_pressed and jump_pressed and not threshold:
				
				# -- CASE 14: player not running, run not pressed, jump just pressed and not over threshold
				#seems like generally, this is the default state for jog_jump when the jump is pressed 
				#-> don't do anything extra unless you want double jumps
				
				# ERROR HANDLING - 
				# this case can be triggered by the following run states:
				#
				# 2:   is_running,  run_pressed, jump_pressed, !threshold
				# ->  !is_running, !run_pressed, jump_pressed, !threshold
				#
				# 4:   is_running, run_pressed, !jump_pressed, !threshold
				# ->  !is_running, !run_pressed, jump_pressed, !threshold
				#
				# 5:   is_running, !run_pressed, jump_pressed,  threshold
				# ->  !is_running, !run_pressed, jump_pressed, !threshold
				#
				# 6:   is_running, !run_pressed, jump_pressed, !threshold
				# ->  !is_running, !run_pressed, jump_pressed, !threshold
				#
				# 7:   is_running, !run_pressed, !jump_pressed,  threshold
				# ->  !is_running, !run_pressed,  jump_pressed, !threshold
				#
				# 8:   is_running, !run_pressed, !jump_pressed, !threshold
				# ->  !is_running, !run_pressed,  jump_pressed, !threshold
				#
				#above cases - the player had run turned on, but because threshold is no longer valid
				#              but because they either let go of the run button or the threshold was
				#              no longer valid now they need to finish their run_jump animation at a slower speed
				if previous_jump_case == 2 or previous_jump_case == 4 or previous_jump_case == 5 or previous_jump_case == 6 or previous_jump_case == 7 or previous_jump_case == 8:
					if is_run_jumping:
						#don't do anything if run_jump is still running
						pass
					else:
						#otherwise reset run states
						is_idle_jumping = false
						is_jog_jumping = false
						is_run_jumping = false
						
						#and reset jump case
						previous_jump_case = -1
				# this case can also be triggered by the following jog states:
				#
				# 13:  !is_running, !run_pressed, jump_pressed,  threshold
				# ->   !is_running, !run_pressed, jump_pressed, !threshold
				#
				# 15:  !is_running, !run_pressed, !jump_pressed,  threshold
				#  ->  !is_running, !run_pressed,  jump_pressed, !threshold
				#
				#cases 13, 15 - the player had run turned off and their threshold states is not really valid
				#               so we make sure that they complete their animations and reset anim states at
				#               the end
				if is_run_jumping and not is_jog_jumping and not is_idle_jumping:
					pass
				elif is_jog_jumping and not is_run_jumping and not is_idle_jumping:
					pass
				elif is_idle_jumping and not is_run_jumping and not is_jog_jumping:
					pass
				else:
					#otherwise reset run states
					is_idle_jumping = false
					is_jog_jumping = false
					is_run_jumping = false
					
					#and reset jump case
					previous_jump_case = -1
			elif not is_running and not run_pressed and not jump_pressed and threshold:
				# -- CASE 15: player is not running, run is not pressed, jump not just pressed and over threshold
				#bug state: can't be over threshold and not running
				
				#set the sprint_timer back to zero because threshold was met // but run is not pressed and not running
				#and we can't sprint while jumping anyway
				sprint_timer = 0.0
				
				# note: this case F/F/F/T will trigger either case 14 F/F/T/F or case 16 F/F/F/F
				# set previous_jump_case to 15 -- anims will be handled by 14 or 16
				previous_jump_case = 15
			elif not is_running and not run_pressed and not jump_pressed and not threshold:
				# -- CASE 16: player not running, run not pressed, jump not pressed and not over threshold
				#seems like the default state for jog_jump
				#-> don't do anything extra unless you want double jumps
				
				# ERROR HANDLING - 
				# this case can be triggered by the following run states:
				#
				# 2:   is_running,  run_pressed,  jump_pressed, !threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				# 4:   is_running, run_pressed,  !jump_pressed, !threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				# 5:   is_running, !run_pressed,  jump_pressed,  threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				# 6:   is_running, !run_pressed,  jump_pressed, !threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				# 7:   is_running, !run_pressed, !jump_pressed,  threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				# 8:   is_running, !run_pressed, !jump_pressed, !threshold
				# ->  !is_running, !run_pressed, !jump_pressed, !threshold
				#
				#above cases - the player had run turned on, but because threshold is no longer valid
				#              but because they either let go of the run button or the threshold was
				#              no longer valid now they need to finish their run_jump animation at a slower speed
				if previous_jump_case == 2 or previous_jump_case == 4 or previous_jump_case == 5 or previous_jump_case == 6 or previous_jump_case == 7 or previous_jump_case == 8:
					if is_run_jumping:
						#don't do anything if run_jump is still running
						pass
					else:
						#otherwise reset run states
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
					pass
				elif is_jog_jumping and not is_run_jumping and not is_idle_jumping:
					pass
				elif is_idle_jumping and not is_run_jumping and not is_jog_jumping:
					pass
				else:
					#otherwise reset run states
					is_idle_jumping = false
					is_jog_jumping = false
					is_run_jumping = false
					
					#and reset jump case
					previous_jump_case = -1

		#sanity check -- set jump_timer back to zero if we're done jumping
		is_jumping = (is_run_jumping and jump_timer >= RUN_JUMP_THRESHOLD) or (is_jog_jumping and jump_timer >= IDLE_JUMP_THRESHOLD) or (is_idle_jumping and jump_timer >= IDLE_JUMP_THRESHOLD)
		
		#sanity check -- player not jumping anymore
		# set jump timer back to zero and reset the jump states
		if !is_jumping:
			jump_timer = 0.0
			is_idle_jumping = false
			is_jog_jumping = false
			is_run_jumping = false
	'''
	
	# --- CASE 2 - PLAYER IS NOT JUMPING
	#idle state
	if not movement_ongoing and not is_jumping and jump_pressed:
		#not handling jump states now
		pass
	
	#non-idle states
	if movement_ongoing:
		if not is_jumping:
			
			#sanity check - increment sprint timer if run pressed
			if run_pressed:
				sprint_timer += delta
			else:
				sprint_timer = 0.0
			
			if is_running and run_pressed and jump_pressed and threshold:
				#not handling jumps now
				pass
			elif is_running and run_pressed and jump_pressed and not threshold:
				#not handling jumps now
				pass
			elif is_running and run_pressed and not jump_pressed and threshold:
				pass
			elif is_running and run_pressed and not jump_pressed and not threshold:
				pass
			elif is_running and not run_pressed and jump_pressed and threshold:
				pass
			elif is_running and not run_pressed and jump_pressed and not threshold:
				pass
			elif is_running and not run_pressed and not jump_pressed and threshold:
				pass
			elif is_running and not run_pressed and not jump_pressed and not threshold:
				pass
			elif not is_running and run_pressed and jump_pressed and threshold:
				pass
			elif not is_running and run_pressed and jump_pressed and not threshold:
				pass
			elif not is_running and run_pressed and not jump_pressed and threshold:
				pass
			elif not is_running and run_pressed and not jump_pressed and not threshold:
				pass
			elif not is_running and not run_pressed and jump_pressed and threshold:
				pass
			elif not is_running and not run_pressed and jump_pressed and not threshold:
				pass
			elif not is_running and not run_pressed and not jump_pressed and threshold:
				pass
			elif not is_running and not run_pressed and not jump_pressed and not threshold:
				pass
	
	else:
		sprint_timer = 0.0
		is_running = false
		pass
		
	if !movement_ongoing and not is_idle_jumping and not is_jumping and not is_jog_jumping and not is_run_jumping:
		_set_movement_state(movement_states["Idle"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|idle")
		
	if movement_ongoing and not is_running and not is_jumping and not is_idle_jumping and not is_jog_jumping and not is_run_jumping:
		_set_movement_state(movement_states["Jog"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jog")
	
	if movement_ongoing and is_running and not is_jumping and not is_idle_jumping and not is_jog_jumping and not is_run_jumping:
		_set_movement_state(movement_states["Run"])
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run")
	
	if !movement_ongoing and is_jumping and is_idle_jumping and not is_jog_jumping and not is_run_jumping:
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jump")
	elif movement_ongoing and is_jumping and is_jog_jumping and not is_idle_jumping and not is_run_jumping:
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jump")
	elif movement_ongoing and is_jumping and is_run_jumping and not is_idle_jumping and not is_jog_jumping:
		$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run_jump")
	
	'''
	# Movement state logic
	if is_movement_ongoing():
		if Input.is_action_pressed("Run"):
			sprint_timer += delta

			if sprint_timer >= SPRINT_THRESHOLD:
				if !is_running and !is_jumping:
					is_running = true
				_set_movement_state(movement_states["Run"])
				if is_jumping:
					$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run_jump")
					
					jump_timer += delta
					if jump_timer >= RUN_JUMP_THRESHOLD:
						is_jumping = false
						jump_timer = 0.0
				else:
					$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run")
			else:
				_set_movement_state(movement_states["Jog"])
				if is_jumping and is_running:
					$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|run_jump")
					
				
				if is_jumping:
					
					$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jump")
					jump_timer += delta
					if jump_timer >= IDLE_JUMP_THRESHOLD:
						is_jumping = false
						jump_timer = 0.0
				else:
					$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jog")
		else:
			is_running = false
			sprint_timer = 0.0
			_set_movement_state(movement_states["Jog"])
			if is_jumping:
				
				$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jump")
				jump_timer += delta
				if jump_timer >= IDLE_JUMP_THRESHOLD:
					is_jumping = false
					jump_timer = 0.0
			else:
				$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jog")
	'''
	'''
	else:
		sprint_timer = 0.0
		_set_movement_state(movement_states["Idle"])
		if is_jumping:
			
			$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|jump")
			jump_timer += delta
			if jump_timer >= IDLE_JUMP_THRESHOLD:
				is_jumping = false
				jump_timer = 0.0
		else:
			$CharacterModel/character_mixamo/AnimationPlayer.play("Armature|idle")
	'''
	# Movement
	if is_movement_ongoing():
		move_direction = movement_direction.rotated(Vector3.UP, cam_rotation)

		var target_velocity := move_direction.normalized() * speed
		
		if is_jumping and !is_running:
			velocity.x = 0
			velocity.z = 0
		else:
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

	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

	

func _set_movement_state(state: Dictionary):
	speed = state["movement_speed"]
	acceleration = state["acceleration"]

	#direct assignment (no Tween, no path resolution)
	animation_tree.set("parameters/movement_blend/blend_position", state["id"])
	animation_tree.set("parameters/movement_anim_speed/scale", state["animation_speed"])

func is_movement_ongoing() -> bool:
	return movement_direction != Vector3.ZERO
