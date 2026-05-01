extends CharacterBody3D

const stand_height = 1.3
const crouch_height = 0.7
const crouch_speed = 3
const first_speed = 2.0
var SPEED = first_speed
const JUMP_VELOCITY = 6
const MOUSE_SENSITIVITY = 0.005
var timer = 0
var sprint_delay = 0.4
var sec_speed = 3.0

const bob_speed = 16.0
const bob_amount = 0.05

const weapon_bob_speed = 16.0
const weapon_bob_amount = 20.0

var bob_time = 0.0
var original_camera_pos
var original_weapon_pos

var camera_roll = 0.0

const SHOOT_LIFT = 10.0
var shoot_lift_current = 0.0
const SHOOT_TILT_MAX = 5.0
var shoot_tilt_current = 0.0
var shoot_tilt_target = 0.0
var shoot_tilt_phase = 0

var shoot_cooldown = 0.0
const SHOOT_COOLDOWN_TIME = 0.2

var health = 100
var armor = 0
var death_sound_played := false
var is_crouching = false

const WALK_ACCELERATION = 99999.0
var current_speed = 0.0

# ── Bhop / Air Strafing ──────────────────────────────────────────────
const AIR_ACCEL    = 800.0   # 空中加速度（越大 strafe 越灵敏）
const AIR_MAX_SPEED = 0.8    # 空中每帧 wishspeed 上限
const FRICTION     = 8.0     # 地面摩擦力
const MAX_VELOCITY = 30.0    # 水平速度绝对上限

var was_on_floor := false
var jump_queued  := false    # 跳跃排队，提前按下也生效

# 跳蹲：起跳时蹲下可以额外增加跳跃高度
const CROUCHJUMP_BONUS = 3.5  # 跳蹲额外速度
var crouchjump_active := false

# 落地冲击动画
const LAND_DIP = 50.0        # 往下的幅度
var land_dip_current = 0.0   # 当前偏移（正数=往下）
var land_dip_phase = 0       # 0=静止 1=下沉 2=回弹
# ─────────────────────────────────────────────────────────────────────

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
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	health_label.text = str(health)
	armor_label.text = str(armor)
	original_camera_pos = camera.position
	original_weapon_pos = glock.position
	glock.pivot_offset = Vector2(277, 393)
	floor_max_angle = deg_to_rad(75)
	floor_snap_length = 0.6
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
	if health <= 0:
		return
	health -= damage
	if health <= 0:
		health = 0
		if not death_sound_played:
			death_sound_played = true
			death_sound.play()

func shoot():
	if gun_ray.is_colliding():
		var target = gun_ray.get_collider()
		if target.has_method("take_damage"):
			target.take_damage(45)

# Quake 风格加速函数
func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var cur = velocity.dot(wish_dir)
	var add = wish_speed - cur
	if add <= 0.0:
		return
	var accel_speed = min(accel * wish_speed * delta, add)
	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z

# 地面摩擦力
func _apply_friction(delta: float) -> void:
	var spd = Vector2(velocity.x, velocity.z).length()
	if spd < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var new_spd = max(spd - spd * FRICTION * delta, 0.0)
	velocity.x *= new_spd / spd
	velocity.z *= new_spd / spd

func _physics_process(delta: float) -> void:
	health_label.text = str(health)
	armor_label.text = str(armor)
	if camera_pivot.rotation.x > deg_to_rad(55):
		lambda_icon.visible = true
	else:
		lambda_icon.visible = false

	# 重力
	if not is_on_floor():
		velocity += get_gravity() * delta * 2

	is_crouching = Input.is_action_pressed("crouch")
	if crouchjump_active and not is_on_floor():
		# 跳蹲空中：自动站直让头部能进入更高的空间
		collision.shape.height = stand_height
		camera_pivot.position.y = stand_height
	elif is_crouching:
		collision.shape.height = crouch_height
		camera_pivot.position.y = crouch_height
	else:
		collision.shape.height = stand_height
		camera_pivot.position.y = stand_height

	# 射击
	if Input.is_action_just_pressed("shoot") and shoot_cooldown <= 0.0:
		shoot()
		shoot_lift_current = SHOOT_LIFT
		shoot_tilt_phase = 1
		shoot_tilt_target = SHOOT_TILT_MAX
		shoot_cooldown = SHOOT_COOLDOWN_TIME
	shoot_cooldown = max(0.0, shoot_cooldown - delta)

	# 跳跃排队：提前按下 Space 也生效
	if Input.is_action_just_pressed("ui_accept"):
		jump_queued = true

	# 落地瞬间跳（bhop 核心：保留水平动量直接起跳）
	if is_on_floor():
		if jump_queued:
			if is_crouching:
				# 跳蹲：蹲着起跳给额外高度，同时标记空中蹲状态
				velocity.y = JUMP_VELOCITY + CROUCHJUMP_BONUS
				crouchjump_active = true
			else:
				velocity.y = JUMP_VELOCITY
				crouchjump_active = false
			jump_queued = false
		elif was_on_floor:
			_apply_friction(delta)
			crouchjump_active = false
		# 落地冲击：从空中落到地面触发
		if not was_on_floor:
			land_dip_current = LAND_DIP
			land_dip_phase = 1

	was_on_floor = is_on_floor()

	# 移动输入
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if is_on_floor() and velocity.y <= 0:
		# 地面：原有加速手感
		if wish_dir != Vector3.ZERO:
			timer += delta
			var target_spd = sec_speed if timer >= sprint_delay else first_speed
			if is_crouching:
				target_spd = crouch_speed
			current_speed = move_toward(current_speed, target_spd, WALK_ACCELERATION * delta)
		else:
			timer = 0
			current_speed = move_toward(current_speed, 0, WALK_ACCELERATION * delta)
		velocity.x = wish_dir.x * current_speed
		velocity.z = wish_dir.z * current_speed
	else:
		# 空中：Quake Air Strafing，方向键+鼠标左右转向可以加速
		if wish_dir != Vector3.ZERO:
			_accelerate(wish_dir, AIR_MAX_SPEED, AIR_ACCEL, delta)
		# 限制水平最大速度
		var horiz = Vector2(velocity.x, velocity.z)
		if horiz.length() > MAX_VELOCITY:
			horiz = horiz.normalized() * MAX_VELOCITY
			velocity.x = horiz.x
			velocity.z = horiz.y

	# ── 台阶：依靠 floor_max_angle + floor_snap 自动处理 ──

	# Camera & Weapon Bob
	var moving_horiz = Vector2(velocity.x, velocity.z).length() > 0.5

	if moving_horiz:
		bob_time += delta * bob_speed
	else:
		var target_bob = round(bob_time / PI) * PI
		bob_time = move_toward(bob_time, target_bob, bob_speed * delta)

	if is_on_floor() and moving_horiz:
		var bob_offset_y = sin(bob_time) * bob_amount
		camera.position.y = original_camera_pos.y + bob_offset_y
		camera.position.x = original_camera_pos.x
	else:
		camera.position = camera.position.lerp(original_camera_pos, delta * 10)

	camera.rotation_degrees.z = 0.0

	shoot_lift_current = move_toward(shoot_lift_current, 0.0, 15.0 * delta)
	shoot_tilt_current = move_toward(shoot_tilt_current, shoot_tilt_target, 50.0 * delta)
	if shoot_tilt_phase == 1 and abs(shoot_tilt_current - shoot_tilt_target) < 0.5:
		shoot_tilt_phase = 2
		shoot_tilt_target = 0.0
	elif shoot_tilt_phase == 2 and abs(shoot_tilt_current) < 0.1:
		shoot_tilt_phase = 0
		shoot_tilt_current = 0.0

	# 落地冲击动画：下沉再回弹
	if land_dip_phase == 1:
		# 快速下沉到最低点
		land_dip_current = move_toward(land_dip_current, 0.0, 180.0 * delta)
		if land_dip_current <= 0.1:
			land_dip_current = -LAND_DIP * 0.4  # 回弹到上方
			land_dip_phase = 2
	elif land_dip_phase == 2:
		# 从上方缓回正中
		land_dip_current = move_toward(land_dip_current, 0.0, 120.0 * delta)
		if abs(land_dip_current) < 0.1:
			land_dip_current = 0.0
			land_dip_phase = 0

	if is_on_floor() and moving_horiz:
		var weapon_bob_offset_y = 0.0 if shoot_lift_current > 0.0 else max(0.0, sin(bob_time) * weapon_bob_amount)
		var weapon_bob_offset_x = 0.0 if shoot_lift_current > 0.0 else sin(bob_time * 0.5) * weapon_bob_amount * 0.4
		var weapon_target_x = original_weapon_pos.x + weapon_bob_offset_x
		var weapon_target_y = max(original_weapon_pos.y, original_weapon_pos.y + weapon_bob_offset_y + shoot_lift_current) + land_dip_current
		glock.position.x = lerp(glock.position.x, weapon_target_x, delta * 12)
		glock.position.y = lerp(glock.position.y, weapon_target_y, delta * 12)
	else:
		glock.position = glock.position.lerp(Vector2(original_weapon_pos.x, original_weapon_pos.y + shoot_lift_current + land_dip_current), delta * 10)
		glock.position.y = max(original_weapon_pos.y, glock.position.y)

	glock.rotation_degrees = shoot_tilt_current

	move_and_slide()


func _on_resume_pressed() -> void:
	pass
