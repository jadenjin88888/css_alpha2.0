extends CharacterBody3D

const stand_height = 1.2
const crouch_height = 0.7
const crouch_speed = 3
const first_speed = 3.0
var SPEED = first_speed
const JUMP_VELOCITY = 6
const MOUSE_SENSITIVITY = 0.005
var timer = 0
var sprint_delay = 0.0
var sec_speed = 5.0

const bob_speed = 8.0
const bob_amount = 0.04

const weapon_bob_speed = 8.0
const weapon_bob_amount = 2.5

var bob_time = 0.0
var original_camera_pos
var original_weapon_pos

# Gmod风格：头部roll（Z轴倾斜）
var camera_roll = 0.0

# 开枪上抬：目标偏移量和当前偏移量
const SHOOT_LIFT = 10.0
var shoot_lift_current = 0.0
# 开枪倾斜：两阶段摆动，先左上再右上再回正
const SHOOT_TILT_MAX = 5.0
var shoot_tilt_current = 0.0
var shoot_tilt_target = 0.0
var shoot_tilt_phase = 0  # 0=静止 1=往左上 2=往右上 3=回正

var shoot_cooldown = 0.0
const SHOOT_COOLDOWN_TIME = 0.2

var health = 100
var armor = 0
var is_crouching = false

# 行走加速度：0.2秒内从0加速到10，加速度 = 10/0.2 = 50
const WALK_ACCELERATION = 5000.0
# 当前水平速度大小（用于加速度计算）
var current_speed = 0.0

@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/Camera3D
@onready var collision = $CollisionShape3D
@onready var death_sound = $death_sound
@onready var health_label = get_node("../ui/hud/health")
@onready var armor_label = get_node("../ui/hud/armor")
@onready var glock = get_node("../ui/glock")
@onready var gun_ray = $CameraPivot/Camera3D/gun_ray
@onready var pause_menu = get_node("../ui/Pausemenu")
@onready var lambda_icon = get_node("../ui/hud/lambda")


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	health_label.text = str(health)
	armor_label.text = str(armor)
	original_camera_pos = camera.position
	original_weapon_pos = glock.position
	# pivot在枪的中间底部，旋转更自然
	glock.pivot_offset = Vector2(277, 393)
	# 台阶设置
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3
	max_slides = 6

func _input(event):
	if event.is_action_pressed("pause") and not get_tree().paused:
		pause_menu.open_menu()

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func take_damage(damage):
	health -= damage
	if health <= 0:
		health = 0
		death_sound.play()

func shoot():
	if gun_ray.is_colliding():
		var target = gun_ray.get_collider()
		if target.has_method("take_damage"):
			target.take_damage(45)

func _physics_process(delta: float) -> void:
	health_label.text = str(health)
	armor_label.text = str(armor)
	if camera_pivot.rotation.x > deg_to_rad(55):
		lambda_icon.visible = true
	else:
		lambda_icon.visible = false

	if not is_on_floor():
		velocity += get_gravity() * delta * 3

	is_crouching = Input.is_action_pressed("crouch")

	if is_crouching:
		collision.shape.height = crouch_height
		camera_pivot.position.y = crouch_height
		SPEED = crouch_speed
	else:
		collision.shape.height = stand_height
		camera_pivot.position.y = stand_height
		SPEED = first_speed

	if Input.is_action_just_pressed("shoot") and shoot_cooldown <= 0.0:
		shoot()
		shoot_lift_current = SHOOT_LIFT
		shoot_tilt_phase = 1
		shoot_tilt_target = SHOOT_TILT_MAX
		shoot_cooldown = SHOOT_COOLDOWN_TIME

	shoot_cooldown = max(0.0, shoot_cooldown - delta)

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		timer += delta

		if timer >= sprint_delay:
			SPEED = sec_speed
		else:
			SPEED = first_speed

		# 用加速度平滑加速到目标速度，1秒内从0到10
		current_speed = move_toward(current_speed, SPEED, WALK_ACCELERATION * delta)

		bob_time += delta * bob_speed

		# 只有上下bob，没有左右摇摆
		var bob_offset_y = sin(bob_time) * bob_amount
		camera.position.y = original_camera_pos.y + bob_offset_y
		camera.position.x = original_camera_pos.x

		# Gmod风格：头部Z轴roll（走路时轻微左右摇头）
		camera_roll = sin(bob_time * 0.5) * 0.8
		camera.rotation_degrees.z = camera_roll

		# 枪的bobbing + 开枪上抬
		shoot_lift_current = move_toward(shoot_lift_current, 0.0, 15.0 * delta)
		# 两阶段倾斜摆动
		shoot_tilt_current = move_toward(shoot_tilt_current, shoot_tilt_target, 50.0 * delta)
		if shoot_tilt_phase == 1 and abs(shoot_tilt_current - shoot_tilt_target) < 0.5:
			shoot_tilt_phase = 2
			shoot_tilt_target = 0.0
		elif shoot_tilt_phase == 2 and abs(shoot_tilt_current) < 0.1:
			shoot_tilt_phase = 0
			shoot_tilt_current = 0.0
		var weapon_bob_offset_y = 0.0 if shoot_lift_current > 0.0 else max(0.0, sin(bob_time) * weapon_bob_amount)
		var weapon_bob_offset_x = 0.0 if shoot_lift_current > 0.0 else sin(bob_time * 0.5) * weapon_bob_amount * 0.4
		var weapon_target_x = original_weapon_pos.x + weapon_bob_offset_x
		var weapon_target_y = max(original_weapon_pos.y, original_weapon_pos.y + weapon_bob_offset_y + shoot_lift_current)
		# Gmod风格：武器有轻微延迟跟随
		glock.position.x = lerp(glock.position.x, weapon_target_x, delta * 12)
		glock.position.y = lerp(glock.position.y, weapon_target_y, delta * 12)
		glock.rotation_degrees = shoot_tilt_current

		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		timer = 0
		# 松开按键时也平滑减速
		current_speed = move_toward(current_speed, 0, WALK_ACCELERATION * delta)
		# bob_time 平滑归零到最近的整数π，避免摄像头跳变
		var target_bob = round(bob_time / PI) * PI
		bob_time = move_toward(bob_time, target_bob, bob_speed * delta)
		# roll平滑回正
		camera_roll = move_toward(camera_roll, 0.0, 3.0 * delta)
		camera.rotation_degrees.z = camera_roll
		# 开枪上抬也继续衰减
		shoot_lift_current = move_toward(shoot_lift_current, 0.0, 15.0 * delta)
		shoot_tilt_current = move_toward(shoot_tilt_current, shoot_tilt_target, 50.0 * delta)
		if shoot_tilt_phase == 1 and abs(shoot_tilt_current - shoot_tilt_target) < 0.5:
			shoot_tilt_phase = 2
			shoot_tilt_target = 0.0
		elif shoot_tilt_phase == 2 and abs(shoot_tilt_current) < 0.1:
			shoot_tilt_phase = 0
			shoot_tilt_current = 0.0
		glock.position = glock.position.lerp(Vector2(original_weapon_pos.x, original_weapon_pos.y + shoot_lift_current), delta * 10)
		glock.position.y = max(original_weapon_pos.y, glock.position.y)
		glock.rotation_degrees = shoot_tilt_current
		camera.position = camera.position.lerp(original_camera_pos, delta * 10)

		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed

	# 台阶：撞到墙时自动往上推
	if is_on_floor() and get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var col = get_slide_collision(i)
			if col.get_normal().y < 0.1:
				velocity.y = 6.0
				break

	move_and_slide()


func _on_resume_pressed() -> void:
	pass # Replace with function body.
