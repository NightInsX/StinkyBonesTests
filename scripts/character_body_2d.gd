extends CharacterBody2D


const SPEED = 300.0
const Ecolocalización = preload("res://scenes/echo.tscn")

@export var wave_max_radius: float = 500.0
@export var wave_duration: float = 0.6
@export var wave_cooldown: float = 0.5  # evita spamear el botón

var cooldown := Timer.new()

func _ready() -> void:
	add_child(cooldown)
	cooldown.wait_time = wave_cooldown
	cooldown.one_shot = true


func _physics_process( _delta: float) -> void:
	var direction_x := Input.get_axis("Left", "Right")
	var direction_y := Input.get_axis("Up", "Down")

	velocity.x = direction_x * SPEED
	velocity.y = direction_y * SPEED
	move_and_slide()


# El Timer actúa de enfriamiento: mientras esté parado se puede volver a
# lanzar. Con one_shot se para solo al expirar, así que no hay que resetearlo.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Echo") and cooldown.is_stopped():
		emitir_onda()


func emitir_onda() -> void:
	var wave := Ecolocalización.instantiate() as Echo
	# Hija de la niña, no de la escena: así la onda nace pegada a ella.
	add_child(wave)
	# Ojo: al ser hija hay que posicionarla en coordenadas LOCAL. Si le
	# pusiéramos global_position antes de add_child(), su position ya valdría
	# (514, 349) y al colgar de la niña se sumaría otra vez el transform del
	# padre, dejando la onda en (1028, 698), en el pasillo de al lado.
	wave.position = Vector2.ZERO
	wave.max_radius = wave_max_radius
	wave.duration = wave_duration
	cooldown.start()

	print("[personaje] onda lanzada en ", wave.global_position, " radio=", wave.max_radius)
