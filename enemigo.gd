extends CharacterBody2D

const Ecolocalización = preload("res://scenes/echo.tscn")

@export var velocidad_max: float = 150.0
@export var frenado: float = 900.0
@export var llegada: float = 12.0  # distancia a la que se considera que ha llegado
@export var pausa_min: float = 0.5  # segundos parado entre destino y destino
@export var pausa_max: float = 1.8
@export var margen: float = 40.0  # no se acerca a los bordes del mapa

@export var onda_max_radius: float = 200.0
@export var onda_duration: float = 0.7
@export var onda_intervalo: float = 2  # media entre lans y lans

@export var distancia_carga: float = 600.0  # si la oye más cerca de esto, va a por ella
@export var memoria_segundos: float = 3.5  # cuánto recuerda dónde la oyó

@onready var _oido: Area2D = $Oido

var _destino: Vector2 = Vector2.ZERO
var _pausa: float = 0.0
var _espera_onda: float = 0.0
var _memoria: float = 0.0
var _ultima_onda_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_destino = _punto_aleatorio()
	# Que no dispare en el mismo instante que la Girl, para no solaparse.
	_espera_onda = randf_range(0.4, onda_intervalo)
	print("[enemigo] primera meta ", _destino)
	# Oye las ondas de la Girl; las suyas van en otra capa, así que no se
	# oye a sí mismo.
	if _oido == null:
		push_warning("enemigo.gd: falta el Area2D hijo 'Oido', no oirá a la Girl")
	else:
		_oido.collision_mask = Echo.CAPA_ONDA_JUGADORA
		_oido.area_entered.connect(_on_onda_entrada)


func _physics_process(delta: float) -> void:
	_gastar_memoria(delta)
	_moverse(delta)
	_lanzar_onda(delta)


func _on_onda_entrada(area: Area2D) -> void:
	if not area.is_in_group(Echo.AREA_GROUP):
		return
	var onda := area.get_parent() as Echo
	if onda == null:
		return

	_ultima_onda_pos = onda.global_position

	_memoria = memoria_segundos
	print("[enemigo] OÍDO: Girl en ", _ultima_onda_pos,
		" dist=", global_position.distance_to(_ultima_onda_pos),
		" recuerda ", memoria_segundos, "s")


func _gastar_memoria(delta: float) -> void:
	if _memoria <= 0.0:
		return
	_memoria -= delta
	if _memoria <= 0.0:
		_memoria = 0.0
		print("[enemigo] se le ha pasado: vuelve a pasearse")


# Carga contra el punto que oyó, si aún lo recuerda y no está demasiado lejos.
func _cargando() -> bool:
	return _memoria > 0.0 \
		and global_position.distance_to(_ultima_onda_pos) < distancia_carga


func _moverse(delta: float) -> void:
	# Cargar tiene prioridad: si no, el enemigo se pasea sin enterarse.
	if _cargando():
		_ir_a(_ultima_onda_pos, delta)
		return

	# Está esperando entre destinos: frena hasta quedarse quieto.
	if _pausa > 0.0:
		_pausa -= delta
		_frenar(delta)
		return

	if global_position.distance_to(_destino) <= llegada:
		_pausa = randf_range(pausa_min, pausa_max)
		_destino = _punto_aleatorio()
		print("[enemigo] nueva meta ", _destino)
		_frenar(delta)
		return

	_ir_a(_destino, delta)


func _ir_a(punto: Vector2, _delta: float) -> void:
	velocity = (punto - global_position).normalized() * velocidad_max
	move_and_slide()


func _frenar(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, frenado * delta)
	move_and_slide()


func _lanzar_onda(delta: float) -> void:
	_espera_onda -= delta
	if _espera_onda > 0.0:
		return
	_espera_onda = randf_range(onda_intervalo * 0.7, onda_intervalo * 1.3)

	var wave := Ecolocalización.instantiate() as Echo

	wave.capa = Echo.CAPA_ONDA_ENEMIGA
	wave.max_radius = onda_max_radius
	wave.duration = onda_duration
	add_child(wave)

	wave.top_level = true
	wave.global_position = global_position
	
	wave.rotation = randf() * TAU

	print("[enemigo] onda lanzada en ", wave.global_position, " radio=", wave.max_radius)



func _punto_aleatorio() -> Vector2:
	var area := get_viewport_rect().grow(-margen)
	return Vector2(
		randf_range(area.position.x, area.end.x),
		randf_range(area.position.y, area.end.y)
	)
