extends CharacterBody2D


const SPEED = 250.0
const Ecolocalización = preload("res://scenes/echo.tscn")

@export var wave_max_radius: float = 1400.0
@export var wave_duration: float = 0.9
@export var wave_cooldown: float = 0.5  # evita spamear el botón

var cooldown := Timer.new()

@onready var _oido: Area2D = $Oido


func _ready() -> void:
	add_child(cooldown)
	cooldown.wait_time = wave_cooldown
	cooldown.one_shot = true
	
	if _oido == null:
		push_warning("character_body_2d.gd: falta el Area2D hijo 'Oido', no oirá nada")
	else:
		_oido.collision_mask = Echo.CAPA_ONDA_ENEMIGA
		_oido.area_entered.connect(_on_onda_entrada)


func _physics_process( _delta: float) -> void:
	var direction_x := Input.get_axis("Left", "Right")
	var direction_y := Input.get_axis("Up", "Down")

	velocity.x = direction_x * SPEED
	velocity.y = direction_y * SPEED
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Echo") and cooldown.is_stopped():
		emitir_onda()


func _on_onda_entrada(area: Area2D) -> void:
	if not area.is_in_group(Echo.AREA_GROUP):
		return
	var onda := area.get_parent() as Echo
	if onda == null:
		return
	print("[jugadora] OÍDO: onda desde ", onda.global_position, " radio=", onda.radio_actual())


func emitir_onda() -> void:
	var wave := Ecolocalización.instantiate() as Echo

	wave.capa = Echo.CAPA_ONDA_JUGADORA
	wave.max_radius = wave_max_radius
	wave.duration = wave_duration
	add_child(wave)
	
	wave.top_level = true
	wave.global_position = global_position
	wave.rotation = (get_global_mouse_position() - global_position).angle()
	cooldown.start()

	print("[personaje] onda lanzada en ", wave.global_position, " radio=", wave.max_radius, " dir=", wave.rotation)
