extends CharacterBody3D

@export var speed = 5.0
@export var damage = 20
@export var attack_range = 5
@export var attack_cd = 2
@export var enemy_health = 200


var attack_timer = 0.0
var player
var is_dead = false

var slow_timer = 0.0
var slow_duration = 0.5   
var slow_multiplier = 0.3 

func take_damage(damage):
	if is_dead:
		return

	enemy_health -= damage

	slow_timer = slow_duration

	if enemy_health <= 0:
		enemy_health = 0
		die()

	enemy_health -= damage

	if enemy_health <= 0:
		enemy_health = 0
		die()

func die():
	is_dead = true
	velocity = Vector3.ZERO
	print("enemy dead")
	

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if player == null:
		return

	# ⭐ 更新减速时间
	if slow_timer > 0:
		slow_timer -= delta

	var distance = global_position.distance_to(player.global_position)

	attack_timer -= delta

	if distance < attack_range and attack_timer <= 0:
		player.take_damage(damage)
		attack_timer = attack_cd

	var direction = player.global_position - global_position
	direction.y = 0
	direction = direction.normalized()


	var current_speed = speed
	if slow_timer > 0:
		current_speed *= slow_multiplier

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	rotation.y = atan2(-direction.x, -direction.z)

	move_and_slide()
