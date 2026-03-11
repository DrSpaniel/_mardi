extends CharacterBody3D

# Player nodes
@onready var neck: Node3D = $neck
@onready var head: Node3D = $neck/head
@onready var eyes: Node3D = $neck/head/eyes
@onready var standing_collision: CollisionShape3D = $standing_collision
@onready var crouched_collision: CollisionShape3D = $crouched_collision
@onready var crouchjump_collision: CollisionShape3D = $crouchjump_collision
@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var camera_3d: Camera3D = $neck/head/eyes/Camera3D
@onready var animation_player: AnimationPlayer = $neck/head/eyes/AnimationPlayer
@onready var interactcast: RayCast3D = $neck/head/eyes/interactcast
@onready var texture_rect: TextureRect = $neck/head/eyes/Camera3D/CanvasLayer2/Control/TextureRect


# Debug States
var debug_enabled = false

# in order: crouch/slide, jump, wallrun, wallkick
var crouch_enabled = true
var jump_enabled = true
var wallrun_enabled = true
var wallkick_enabled = true

# States
var walking := false
var sprinting := false
var crouched := false
var freelook := false
var sliding := false
var was_in_air = false

# NEW: Centralized crouch state management
var want_to_stand := false  # Player wants to stand but ceiling prevents it

# Slide vars
var slide_timer = 0.0
var slide_timer_max = 1.0
var slide_vector = Vector2.ZERO
var slide_speed = 15

# Jump vars
var last_velocity = Vector3.ZERO
var horizontal_velocity = Vector2(velocity.x, velocity.z)
@export var jump_velocity = 5
var crouch_counter = 0.0
@export var min_crouch_counter = 8.0
@export var max_crouch_counter = 15.0
var is_charging = false

# Wall system vars - SIMPLIFIED
enum WallState {
	NONE,
	WALLRUNNING
}

var wall_state = WallState.NONE
var wallrun_timer = 0.0
var max_wallrun_time = 3.0
var wallrun_velocity_set = false

# Wallkick vars
@export var wall_kick_strength_horiz = 4
@export var wall_kick_strength_vert = 5

# Headbob vars
const headbob_sprint_speed = 22
const headbob_walk_speed = 14
const headbob_crouch_speed = 10
const headbob_sprint_intensity = 0.05
const headbob_walk_intensity = 0.05
const headbob_crouch_intensity = 0.05

var headbob_vector = Vector2.ZERO
var headbob_index = 0
var headbob_intensity = 0

# Speed vars
var current_speed = 5.0
const walking_speed = 5.0
const sprint_speed = 8.0
const crouch_speed = 3.0
var wallrun_speed = 20.0

# Movement vars
var crouch_depth = -0.5
var lerp_speed = 10.0
var air_lerp = 3
var freelook_angle = 8

# Air movement vars
@export var air_control_force = 10.0
@export var max_air_speed = 7.5

# Input vars
var direction = Vector3.ZERO
const mouse_sens = 0.25
var mouseinput := true

# Interaction stuff
var lastInteraction
var is_holding = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	# Feature enablers
	if event.is_action_pressed("debug_abilities"):
		debug_enabled = !debug_enabled
		
		if debug_enabled:
			jump_enabled = false
			crouch_enabled = false
			wallrun_enabled = false
			wallkick_enabled = true
			print("debug time!")
		else:
			jump_enabled = true
			crouch_enabled = true
			wallrun_enabled = true
			wallkick_enabled = true
			print("Bye bye debug!")
	
	if event.is_action_pressed("num1") and debug_enabled:
		crouch_enabled = true
		print("crouch enabled!")
		
	if event.is_action_pressed("num2") and debug_enabled:
		jump_enabled = true
		print("jump enabled!")
		
	if event.is_action_pressed("num3") and debug_enabled:
		wallrun_enabled = true
		print("wallrun enabled!")
		
	if event.is_action_pressed("num4") and debug_enabled:
		wallkick_enabled = true
		print("wallkick enabled!")
	
	# Mouse move logic
	if event.is_action_pressed("esc"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouseinput = false
		
	if event.is_action_pressed("click"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		mouseinput = true
		
	if mouseinput == true:
		if event is InputEventMouseMotion:
			if freelook:
				neck.rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
				neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-80), deg_to_rad(80))
			else:
				rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
			head.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta: float) -> void:
	# Getting movement input
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	horizontal_velocity = Vector2(velocity.x, velocity.z)
	
	if Input.is_action_just_pressed("debug"):
		print("-------DEBUG-------")
		print("wall_state:", WallState.keys()[wall_state])
		print("walking:", walking)
		print("sprinting:", sprinting)
		print("velocity.y:", velocity.y)
		print("horiz velocity", horizontal_velocity.length())
		print("want_to_stand:", want_to_stand)
		print("crouched:", crouched)
	
	if Input.is_action_just_pressed("reset"):
		global_position = Vector3.ZERO
		velocity = Vector3.ZERO
		rotation = Vector3.ZERO
		head.rotation = Vector3.ZERO
		reset_wall_state()
	
	# Handle movement states - NEW STREAMLINED VERSION
	handle_movement_states_new(delta, input_dir)
	
	# Handle freelook
	handle_freelook(delta)
	
	# Handle sliding
	handle_sliding_new(delta)
	
	# Handle headbob
	handle_headbob(delta, input_dir)
	
	# Handle player movement
	handle_player_movement(delta, input_dir)
	
	# Handle wall system
	handle_wall_system(delta, input_dir)
	
	# Handle gravity
	handle_gravity(delta)
	
	var was_airborne = not is_on_floor()
	
	last_velocity = velocity
	move_and_slide()
	
	# Check for air-to-ground transition slide
	handle_air_to_slide_transition(was_airborne)
	
	was_in_air = was_airborne
	
	# Handle interactions
	handle_interactions_raycast()
	
	# Handle viewmodel stuff
	handle_viewmodel(lastInteraction)

# NEW: Streamlined movement state handling
func handle_movement_states_new(delta: float, input_dir: Vector2):
	"""Unified movement state handling with proper ceiling checks"""
	
	# Check if player wants to crouch or stand
	var jump_input_pressed = Input.is_action_pressed("jump")
	var ceiling_blocked = ray_cast_3d.is_colliding()
	
	# Check for slide initiation BEFORE changing states
	# This preserves the sprinting state check
	if (is_on_floor() and crouch_enabled and jump_input_pressed and not sliding and 
		horizontal_velocity.length() > 7 and sprinting and input_dir != Vector2.ZERO):
		start_slide(input_dir)
	
	# Determine desired crouch state
	var should_be_crouched = false
	
	if is_on_floor() and crouch_enabled and (jump_input_pressed or sliding):
		should_be_crouched = true
		want_to_stand = false
	else:
		# Player wants to stand
		want_to_stand = true
		if ceiling_blocked:
			# Can't stand due to ceiling, stay crouched
			should_be_crouched = true
		else:
			# Can stand freely
			should_be_crouched = false
	
	# Apply crouch state
	if should_be_crouched:
		apply_crouch_state(delta)
		
		# Handle jump charging when crouched and on ground
		if is_on_floor() and jump_input_pressed:
			is_charging = true
			crouch_counter += delta * 10.0
			crouch_counter = clamp(crouch_counter, min_crouch_counter, max_crouch_counter)
			
	else:
		apply_stand_state(delta)
		
		# Handle jump release when standing up
		if Input.is_action_just_released("jump") and jump_enabled and is_on_floor() and is_charging:
			do_jump(crouch_counter)
		elif Input.is_action_pressed("sprint") and is_on_floor():
			# Sprinting
			current_speed = lerp(current_speed, sprint_speed, delta * lerp_speed/4)
			if horizontal_velocity.length() > 7:
				walking = false
				sprinting = true
				crouched = false
		else:
			# Walking
			current_speed = lerp(current_speed, walking_speed, delta * lerp_speed)
			walking = true
			sprinting = false
			crouched = false

func apply_crouch_state(delta: float):
	"""Apply crouched state consistently"""
	current_speed = lerp(current_speed, crouch_speed, delta * lerp_speed)
	head.position.y = lerp(head.position.y, crouch_depth, delta * lerp_speed)
	standing_collision.disabled = true
	crouched_collision.disabled = false
	
	walking = false
	sprinting = false
	crouched = true

func apply_stand_state(delta: float):
	"""Apply standing state consistently"""
	head.position.y = lerp(head.position.y, 0.0, delta * lerp_speed)
	standing_collision.disabled = false
	crouched_collision.disabled = true
	
	# Reset crouch-related vars when successfully standing
	if not crouched:
		crouch_counter = 0.0
		is_charging = false

func start_slide(input_dir: Vector2):
	"""Initiate sliding"""
	if not sliding:
		sliding = true
		slide_timer = slide_timer_max
		slide_vector = input_dir
		freelook = true
		print("slide begin")

# NEW: Streamlined sliding handler
func handle_sliding_new(delta: float):
	"""Handle sliding with proper ceiling checks"""
	if not sliding:
		return
		
	slide_timer -= delta
	
	# Check if slide should end
	var should_end_slide = false
	var should_jump = false
	
	if slide_timer <= 0:
		print("slide end via timer")
		should_end_slide = true
	elif Input.is_action_just_released("jump"):
		print("slide end via jump release")
		should_end_slide = true
		if jump_enabled and is_charging:
			should_jump = true
	
	if should_end_slide:
		sliding = false
		freelook = false
		
		if should_jump:
			# Only jump if we can stand (no ceiling)
			if not ray_cast_3d.is_colliding():
				do_jump(crouch_counter)
			else:
				print("Can't jump due to ceiling, staying crouched")
		
		# Note: Crouch state will be handled by handle_movement_states_new()
		# which will respect ceiling checks automatically

# Keep all the other functions the same...
func handle_wall_system(delta: float, _input_dir: Vector2):
	"""Centralized wall system handling"""
	var touching_wall = is_on_wall_only()
	
	if touching_wall and wallrun_enabled and wall_state == WallState.NONE:
		# Start wallrunning
		wall_state = WallState.WALLRUNNING
		wallrun_timer = 0.0
		wallrun_velocity_set = false
		print("Started wallrunning")
	
	elif wall_state == WallState.WALLRUNNING:
		if not touching_wall:
			# Left the wall
			reset_wall_state()
			print("Left wall, ending wallrun")
		else:
			# Continue wallrunning
			wallrun_timer += delta
			if wallrun_timer >= max_wallrun_time:
				reset_wall_state()
				print("Wallrun time expired")
			elif Input.is_action_just_pressed("jump") and wallkick_enabled:
				# Perform wallkick - just apply force and end wallrunning
				perform_wallkick()
				reset_wall_state()  # End wallrunning immediately

func perform_wallkick():
	"""Execute a wallkick - just apply force, no state management"""
	var collision = get_last_slide_collision()
	if collision:
		var wall_normal = collision.get_normal()
		print("WALLKICK! Normal:", wall_normal)
		
		# Apply strong force away from wall
		velocity += wall_normal * wall_kick_strength_horiz
		velocity.y = wall_kick_strength_vert
		
func reset_wall_state():
	"""Reset all wall-related state"""
	wall_state = WallState.NONE
	wallrun_timer = 0.0
	wallrun_velocity_set = false

func is_wallrunning() -> bool:
	return wall_state == WallState.WALLRUNNING

func handle_freelook(delta: float):
	"""Handle freelook camera behavior"""
	if Input.is_action_pressed("freelook") or sliding:
		freelook = true
		if sliding:
			eyes.rotation.z = lerp(camera_3d.rotation.z, -deg_to_rad(8), delta * lerp_speed)
		else: 
			eyes.rotation.z = deg_to_rad(-neck.rotation.y * freelook_angle)
	else:
		freelook = false
		neck.rotation.y = lerp(neck.rotation.y, 0.0, delta * lerp_speed * 2.6)
		eyes.rotation.z = lerp(eyes.rotation.z, 0.0, delta * lerp_speed * 2.6)

func handle_headbob(delta: float, input_dir: Vector2):
	"""Handle camera headbob"""
	if sprinting:
		headbob_intensity = headbob_sprint_intensity
		headbob_index += headbob_sprint_speed * delta
	elif walking:
		headbob_intensity = headbob_walk_intensity
		headbob_index += headbob_walk_speed * delta
	elif crouched:
		headbob_intensity = headbob_crouch_intensity
		headbob_index += headbob_crouch_speed * delta
	
	if is_on_floor() and !sliding and input_dir != Vector2.ZERO:
		headbob_vector.y = sin(headbob_index)
		headbob_vector.x = sin(headbob_index/2) + 0.5
		
		eyes.position.y = lerp(eyes.position.y, headbob_vector.y * (headbob_intensity/2), delta*lerp_speed)
		eyes.position.x = lerp(eyes.position.x, headbob_vector.x * (headbob_intensity), delta*lerp_speed)
	else:
		eyes.position.y = lerp(eyes.position.y, 0.0, delta*lerp_speed)
		eyes.position.x = lerp(eyes.position.x, 0.0, delta*lerp_speed)

func handle_player_movement(delta: float, input_dir: Vector2):
	"""Handle player movement with proper air control"""
	
	if is_on_floor():
		# Ground movement - direct velocity control (existing behavior)
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*lerp_speed)
		
		if sliding:
			direction = (transform.basis * Vector3(slide_vector.x, 0, slide_vector.y)).normalized()
			current_speed = (slide_timer + 0.1) * slide_speed
		
		# Apply movement - replace velocity on ground
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)
	
	else:
		# Air movement - additive control (preserve existing momentum)
		if input_dir != Vector2.ZERO:
			var input_vector = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			
			# Add steering force to existing velocity instead of replacing it
			velocity.x += input_vector.x * air_control_force * delta
			velocity.z += input_vector.z * air_control_force * delta
			
			# Optional: Cap maximum horizontal speed to prevent infinite acceleration
			var horizontal_vel = Vector2(velocity.x, velocity.z)
			
			if horizontal_vel.length() > max_air_speed:
				horizontal_vel = horizontal_vel.normalized() * max_air_speed
				velocity.x = horizontal_vel.x
				velocity.z = horizontal_vel.y

func handle_gravity(delta: float):
	"""Handle gravity and wallrun physics"""
	if not is_on_floor():
		if not is_wallrunning():
			velocity += get_gravity() * delta
		else:
			# Wallrunning physics
			if wallrun_timer < 2.2:
				if not wallrun_velocity_set:
					velocity.y = 0.0  # Stop vertical movement
				wallrun_velocity_set = true
				current_speed = lerp(current_speed, wallrun_speed, delta * lerp_speed)
			else:
				print("beginning descent")
				velocity += get_gravity()/3 * delta

func do_jump(charge):
	"""Execute a jump with charge"""
	print("crouch:", int(charge))
	velocity.y = jump_velocity * charge/10
	sliding = false
	is_charging = false
	animation_player.play("jumping")
	crouch_counter = 0.0
	
func handle_air_to_slide_transition(was_airborne: bool):
	"""Handle sliding when landing from air with speed and crouch held"""
	if was_airborne and crouch_enabled and is_on_floor():  # Just landed
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		
		# If moving fast enough, holding crouch, and have horizontal momentum
		if horizontal_speed >= sprint_speed/2 and Input.is_action_pressed("jump"):
			print("=== AIR-TO-SLIDE TRANSITION ===")
			print("Landing speed:", horizontal_speed)
			
			# Convert velocity to local space slide vector (matching coordinate system)
			var world_velocity_normalized = Vector3(velocity.x, 0, velocity.z).normalized()
			var local_velocity = transform.basis.inverse() * world_velocity_normalized
			slide_vector = Vector2(local_velocity.x, local_velocity.z)
			
			# Start sliding using the new unified function
			start_slide(slide_vector)
			
			# Set appropriate states
			crouched = true
			walking = false
			sprinting = false

func handle_interactions_raycast() -> Object:
	if interactcast.is_colliding():
		
		var hit = interactcast.get_collider()
		var normal = interactcast.get_collision_normal()
		
		if lastInteraction:
			print("last interactable object:", lastInteraction.name)
		if !is_holding and hit and hit.name.begins_with("obj") and Input.is_action_just_pressed("use"):
			lastInteraction = hit
			toggle_interactbox(lastInteraction, 0)
			is_holding = true
			
		elif is_floor(normal) and is_holding and lastInteraction and Input.is_action_just_pressed("use") and !lastInteraction.visible:
			print(lastInteraction.name, " should move here!")
			print("looking at ", hit.name)
			if lastInteraction.name.begins_with("obj_") and hit.name.begins_with("ent_"):
				print(lastInteraction.name, " given to ", hit.name)
				if lastInteraction.name.ends_with("apple") and hit.name.ends_with("cow"):
					crouch_enabled = true
					is_holding = false
					hit.play_sound()
				elif lastInteraction.name.ends_with("banana") and hit.name.ends_with("fox"):
					jump_enabled = true
					hit.play_sound()
					is_holding = false
				elif lastInteraction.name.ends_with("grape") and hit.name.ends_with("chimp"):
					wallrun_enabled = true
					hit.play_sound()
					is_holding = false
				
			else:
				move_interactbox_to_floor(interactcast.get_collision_point(), lastInteraction)
			lastInteraction = null
	
	return lastInteraction

func toggle_interactbox(box: Node, toggle: bool):
	var shape = box.get_node_or_null("CollisionShape3D")
	if toggle:
		box.visible = true
		shape.disabled = false
	else:
		box.visible = false
		shape.disabled = true

func is_floor(collider: Vector3) -> bool:
	if collider.y == 1:
		return true
	else: return false

func move_interactbox_to_floor(point: Vector3, box: Node):	
	var new_position = box.global_position
	new_position.x = point.x
	new_position.y = point.y
	new_position.z = point.z
	box.global_position = new_position
	
	toggle_interactbox(box, 1)  # Make it reappear
	is_holding = false

func handle_viewmodel(object: Object):
	if lastInteraction:
		print("holding ", lastInteraction.name)
		texture_rect.visible = true
	elif !lastInteraction:
		print("holding nothing")
		texture_rect.visible = false
	return
