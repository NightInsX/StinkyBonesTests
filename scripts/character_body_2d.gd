extends CharacterBody2D


const SPEED = 300.0
const Ecolocalización = preload("res://scenes/echo.tscn")

@export var wave_max_radius: float = 220.0
@export var wave_duration: float = 0.6
@export var wave_cooldown: float = 0.3  # evita spamear el botón

func _physics_process( _delta: float) -> void:
	var direction_x := Input.get_axis("Left", "Right")
	var direction_y := Input.get_axis("Up", "Down")
	
	velocity.x = direction_x * SPEED
	velocity.y = direction_y * SPEED
	move_and_slide()
	

var _cooldown_timer: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	# Opción A: comprobación continua (útil si el efecto es parte de _process)
	if Input.is_action_just_pressed("Echo") and _cooldown_timer <= 0.0:
		emitir_onda()


func emitir_onda() -> void:
	var wave = Ecolocalización.instantiate()
	wave.global_position = global_position
	wave.max_radius = wave_max_radius
	wave.duration = wave_duration
	get_tree().current_scene.add_child(wave)

	_cooldown_timer = wave_cooldown
