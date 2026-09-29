extends CharacterBody2D


const SPEED = 250.0
const Ecolocalización = preload("res://scenes/echo.tscn")

@export var wave_max_radius: float = 1400.0
@export var wave_duration: float = 0.9
@export var wave_cooldown: float = 0.5  # evita spamear el botón

@export_group("Bloques sensibles")
## Segundos que dura la ralentización al chocar contra un bloque sensible. Se
## reinicia mientras se siga prensada contra el muro, así que sólo se recupera
## al soltarse.
@export_range(0.1, 10.0, 0.1) var ralentizacion_segundos: float = 1.5
## Con qué velocidad se sale multiplicada mientras dura: 0.4 es la mitad
## justa de SPEED por debajo. Poner 1 desactiva la ralentización.
@export_range(0.0, 1.0, 0.05) var factor_ralentizacion: float = 0.45
## Enfriamiento del aviso al enemigo. Sin él, estar prensada contra un bloque
## sensible mandaría una alerta por frame.
@export_range(0.1, 10.0, 0.1) var alerta_enfriamiento: float = 1.5
## Hasta dónde se empuja el punto de impacto por la normal del muro antes de
## pasárselo al enemigo: el contacto cae EN la cara del muro, y si el enemigo
## se fuera justo ahí quedaría prensado contra la pared en vez de llegar al
## sitio donde estaba la Girl.
@export_range(0.0, 256.0, 8.0) var margen_alerta: float = 96.0
## Si el bloque sensible también se enciende al chocar contra él, además de al
## recibir la onda. Apagarlo deja el revelado exclusivo de las ondas.
@export var encender_al_chocar: bool = true

var cooldown := Timer.new()

## Segundos que quedan de ralentización, o 0 si no toca ninguna.
var _ralentizada: float = 0.0
## Segundos que quedan hasta poder volver a avisar al enemigo.
var _alerta_enfriamiento: float = 0.0

## true cuando lleva la llave del laberinto encima. Lo pone Llave al tocarla y lo
## mira Puerta para decidir si se abre. Vive aquí y no en la llave ni en la puerta
## porque la llave no conoce a la puerta y la puerta no tiene por qué saber quién
## la recogió: el estado es de quien lo lleva.
var tiene_llave: bool = false

@onready var _oido: Area2D = $Oido
@onready var _animation_tree: AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback = _animation_tree.get("parameters/playback")


func _ready() -> void:
	Global.overworld = true
	add_child(cooldown)
	cooldown.wait_time = wave_cooldown
	cooldown.one_shot = true
	Global.overworld = true
	_animation_tree.active = true
	add_child(cooldown)


	if _oido == null:
		push_warning("character_body_2d.gd: falta el Area2D hijo 'Oido', no oirá nada")
	else:
		_oido.collision_mask = Echo.CAPA_ONDA_ENEMIGA
		_oido.area_entered.connect(_on_onda_entrada)


func _physics_process( delta: float) -> void:
	var direction_x := Input.get_axis("Left", "Right")
	var direction_y := Input.get_axis("Up", "Down")

	var marcha := SPEED
	if _ralentizada > 0.0:
		marcha *= factor_ralentizacion

	velocity.x = direction_x * marcha
	velocity.y = direction_y * marcha
	move_and_slide()
	_update_animation(direction_x, direction_y)
	_gastar_efectos(delta)
	_chocar_con_sensibles()

func _update_animation(direction_x: float, direction_y: float) -> void:
	var direction := Vector2(direction_x, direction_y)
	if direction != Vector2.ZERO:
		_state_machine.travel("Walk")
		_animation_tree.set("parameters/Walk/blend_position", direction)
	else:
		_state_machine.travel("Idle")

## Baja los contadores de ralentización y de enfriamiento del aviso. Va ANTES
## de mirar las colisiones para que un golpe de este frame ponga el contador a
## tope y no se lo coma el descuento.
func _gastar_efectos(delta: float) -> void:
	if _ralentizada > 0.0:
		_ralentizada = maxf(_ralentizada - delta, 0.0)
	if _alerta_enfriamiento > 0.0:
		_alerta_enfriamiento = maxf(_alerta_enfriamiento - delta, 0.0)


## ¿Ha dado contra un bloque sensible en este frame? Si es así: se ralentiza,
## se enciende el bloque (si `encender_al_chocar`) y se le dice al enemigo dónde
## ha sido el golpe. El choque se mira en las colisiones de deslizamiento y no
## con un Area2D, porque así sólo salta quien choca de verdad y con el punto y
## la normal exactos del contacto.
func _chocar_con_sensibles() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var bloque := col.get_collider() as Bloque
		if bloque == null or not bloque.sensible:
			continue
		_ralentizada = ralentizacion_segundos
		if encender_al_chocar:
			bloque.chocar()
		if _alerta_enfriamiento <= 0.0:
			_alertar_enemigo(col.get_position() + col.get_normal() * margen_alerta)
		return


## Avisa a todos los enemigos del punto del golpe. Va por grupo en vez de por
## una referencia al nodo: el enemigo puede no existir aún, puede haber más de
## uno y la Girl no tiene por qué saber dónde vive.
func _alertar_enemigo(punto: Vector2) -> void:
	_alerta_enfriamiento = alerta_enfriamiento
	var avisados := 0
	for nodo in get_tree().get_nodes_in_group(Enemigo.GRUPO):
		var enemigo := nodo as Enemigo
		if enemigo == null:
			continue
		enemigo.alertar(punto)
		avisados += 1
	print("[jugadora] golpe contra bloque sensible en ", punto,
			", avisa a ", avisados, " enemigo(s)")


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

func _on_zona_muerte_area_entered(_area: Area2D) -> void:
	get_tree().change_scene_to_file("res://scenes/death_scr.tscn")
