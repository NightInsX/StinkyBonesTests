extends CharacterBody2D

const Ecolocalización = preload("res://scenes/echo.tscn")

@export var velocidad_max: float = 150.0
@export var aceleracion: float = 700.0
@export var frenado: float = 900.0
@export var llegada: float = 12.0  # distancia a la que se considera que ha llegado
@export var pausa_min: float = 0.5  # segundos parado entre destino y destino
@export var pausa_max: float = 1.8
@export var margen: float = 160.0  # no se acerca a los bordes del mapa

@export var onda_max_radius: float = 400.0
@export var onda_duration: float = 0.7
@export var onda_intervalo: float = 1.6  # media entre ondas y ondas

@export var distancia_carga: float = 1800.0  # si la oye más cerca de esto, va a por ella
@export var memoria_segundos: float = 8.0  # cuánto recuerda dónde la oyó

@export var atascado_max: float = 0.4  # segundos empujando contra un muro antes de rodearlo
@export var desatasque_tiempo: float = 0.9  # segundos que dura la decision de bordear el muro
@export var paso_rodeo: float = 90.0  # hasta donde prueba un rodeo antes de rendirse
@export var ajuste_malla: float = 40.0  # margen para aceptar un punto casi fuera de la malla
@export var capas_muro: int = 1  # capas de física que cuentan como muro infranqueable

@onready var _oido: Area2D = $Oido
@onready var _agente: NavigationAgent2D = $Agente
@onready var _cuerpo: CollisionShape2D = $CollisionShape2D

var _destino: Vector2 = Vector2.ZERO
var _pausa: float = 0.0
var _espera_onda: float = 0.0
var _memoria: float = 0.0
var _ultima_onda_pos: Vector2 = Vector2.ZERO
var _pos_previa: Vector2 = Vector2.ZERO
var _atascado: float = 0.0
var _ruta_impresa: bool = false

# Estado del desatasque.
var _meta: Vector2 = Vector2.ZERO  # a dónde va ahora mismo, sea carga o paseo
var _bloqueado: bool = false  # este frame ha chocado con un muro de frente
var _borde: Vector2 = Vector2.ZERO  # lado del muro que se decide a bordear
var _borde_t: float = 0.0
var _radio: float = 32.0  # medio ancho del cuerpo, para no apuntar a muros
var _sonda: CircleShape2D
var _espacio: PhysicsDirectSpaceState2D

# Direcciones que se prueban como rodeo, de menos a más apartada del objetivo.
const _RODEOS := [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6, PI]


func _ready() -> void:
	_radio = _medio_cuerpo()
	_sonda = CircleShape2D.new()
	_sonda.radius = _radio
	_pos_previa = global_position
	# Que no dispare en el mismo instante que la Girl, para no solaparse.
	_espera_onda = randf_range(0.4, onda_intervalo)
	# Oye las ondas de la Girl; las suyas van en otra capa, así que no se
	# oye a sí mismo.
	if _oido == null:
		push_warning("enemigo.gd: falta el Area2D hijo 'Oido', no oirá a la Girl")
	else:
		_oido.collision_mask = Echo.CAPA_ONDA_JUGADORA
		_oido.area_entered.connect(_on_onda_entrada)
	# La malla se puede generar al cargar la escena y tarda un frame en
	# sincronizarse, así que la primera meta se sortea con la malla ya en pie.
	await get_tree().physics_frame
	_destino = _punto_aleatorio()
	print("[enemigo] primera meta ", _destino)


func _physics_process(delta: float) -> void:
	_espacio = get_world_2d().direct_space_state
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
		_ruta_impresa = false
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


func _ir_a(punto: Vector2, delta: float) -> void:
	_meta = punto
	_borde_t = maxf(_borde_t - delta, 0.0)

	var siguiente := _destino_libre(_waypoint(_meta))
	var deseada := (siguiente - global_position)
	if deseada.length_squared() > 0.0001:
		deseada = deseada.normalized() * velocidad_max
	else:
		deseada = Vector2.ZERO

	# Acelera en lugar de colocarse a tope de velocidad cada frame. Con la
	# velocidad fija, el deslizamiento que hace move_and_slide al rozar una
	# pared se cancela en el frame siguiente y el cuerpo acaba prensado
	# contra ella en vez de rodearla.
	velocity = velocity.move_toward(deseada, aceleracion * delta)
	move_and_slide()

	_recordar_bloqueo()
	_vigilar_atasco(delta)


# El agente devuelve el siguiente waypoint de la ruta, que no es el destino
# final cuando hay que rodear el pasillo. Si no hay ruta, porque la meta cae
# fuera de la malla, devuelve la posición actual; antes el script se
# rectificaba yendo en línea recta contra el muro que hubiera en medio, que es
# justo lo que lo dejaba clavado. Ahora se va al final real de la ruta.
func _waypoint(meta: Vector2) -> Vector2:
	if _agente == null:
		return meta

	_agente.target_position = meta
	var siguiente := _agente.get_next_path_position()
	if siguiente.distance_to(global_position) >= 1.0:
		_imprimir_ruta()
		return siguiente

	var fin := _agente.get_final_position()
	if fin.distance_to(global_position) >= 1.0:
		return fin
	# Ya está donde se puede llegar: no hay nada que forzar, que frene.
	return global_position


# La malla de navegación está dibujada para un punto, pero el enemigo es un
# cuerpo de 144x136: hay tramos que la ruta da por buenos y su cuerpo no cabe
# (la boca del pasillo, la franja de la derecha). Si apunta a ciegas empuja
# contra la pared para siempre, así que se comprueba el camino con el tamaño
# real del cuerpo y, si está cerrado, se busca el rodeo que más se acerca a la
# meta.
func _destino_libre(siguiente: Vector2) -> Vector2:
	var displacement := siguiente - global_position
	if displacement.length() < 1.0:
		return siguiente
	if _via_libre(global_position, siguiente):
		return siguiente

	var dir := displacement.normalized()
	var hacia_meta := (_meta - global_position).normalized()
	var mejor := Vector2.INF
	var mejor_puntuacion := -INF
	for angulo: float in _RODEOS:
		var cand := global_position + dir.rotated(angulo) * paso_rodeo
		if not _via_libre(global_position, cand):
			continue
		if not _en_malla(cand).is_finite():
			continue
		var puntua := dir.rotated(angulo).dot(hacia_meta) - absf(angulo) * 0.3
		if _borde_t > 0.0:
			puntua += dir.rotated(angulo).dot(_borde) * 0.5
		if puntua > mejor_puntuacion:
			mejor_puntuacion = puntua
			mejor = cand
	if mejor == Vector2.INF:
		# Muralla cerrada en todas direcciones: no hay nada libre a tiro, así
		# que se frena en vez de empujar.
		return global_position
	return mejor


# ¿Puede el cuerpo llegar de aquí a allí sin tocar un muro?
func _via_libre(desde: Vector2, hasta: Vector2) -> bool:
	var dist := desde.distance_to(hasta)
	if dist < 1.0:
		return true
	var pasos := int(dist / maxf(_radio, 1.0)) + 1
	for i in pasos + 1:
		if not _cuerpo_libre(desde.lerp(hasta, float(i) / pasos)):
			return false
	return true


func _cuerpo_libre(punto: Vector2) -> bool:
	if _espacio == null or _sonda == null:
		return true
	var consulta := PhysicsShapeQueryParameters2D.new()
	consulta.shape = _sonda
	consulta.transform = Transform2D(0.0, punto)
	consulta.collision_mask = capas_muro
	consulta.collide_with_bodies = true
	consulta.collide_with_areas = false
	var excepcion: Array[RID] = [get_rid()]
	consulta.exclude = excepcion
	return _espacio.intersect_shape(consulta, 1).is_empty()


# Proyecta el punto sobre la malla. Devuelve Vector2.INF si no hay malla a tiro.
func _en_malla(punto: Vector2) -> Vector2:
	if _agente == null:
		return punto
	var mapa := _agente.get_navigation_map()
	if not mapa.is_valid():
		return Vector2.INF
	# La malla puede construirse en tiempo de ejecución (DTLMapa la genera al
	# cargar la escena) y el servidor necesita un frame para sincronizarla.
	# Antes de esa primera sincronización hay que devolver INF, no preguntar.
	if NavigationServer2D.map_get_iteration_id(mapa) == 0:
		return Vector2.INF
	var cerca := NavigationServer2D.map_get_closest_point(mapa, punto)
	if cerca == Vector2.INF or cerca.distance_to(punto) > ajuste_malla:
		return Vector2.INF
	return cerca


# Imprime la ruta una sola vez por carga, para comprobar en consola que sale
# con varios puntos y está rodeando el pasillo en vez de ir en línea recta.
func _imprimir_ruta() -> void:
	if _ruta_impresa or not _cargando():
		return
	_ruta_impresa = true
	print("[enemigo] ruta de ", _agente.get_current_navigation_path().size(),
		" punto(s) hacia ", _ultima_onda_pos)


# Apunta la dirección del frame: si ha chocado de frente contra un muro estatico
# es que lo tiene delante; si no, la vía está limpia.
func _recordar_bloqueo() -> void:
	_bloqueado = false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if not (col.get_collider() is StaticBody2D):
			continue
		if col.get_normal().dot(velocity) >= 0.0:
			continue
		_bloqueado = true
		return


# Cuando el enemigo lleva un rato sin avanzar contra un muro, hay que buscar
# salida. Antes solo cambiaba la meta de paseo, y como la carga tiene prioridad
# en _moverse, persiguiendo no hacía nada: se quedaba prensado los 3.5 s que
# duraba la memoria, y volvía a hacerlo con la siguiente onda. Ahora el rodeo se
# decide aparte de la meta, así que también sirve cargando.
func _vigilar_atasco(delta: float) -> void:
	var avanzando := global_position.distance_to(_pos_previa) > velocidad_max * delta * 0.5
	_pos_previa = global_position

	if _bloqueado or (not avanzando and not _en_el_final_de_la_ruta()):
		_atascado += delta
	else:
		_atascado = 0.0

	if _atascado < atascado_max:
		return
	_atascado = 0.0
	_desatascar()


func _desatascar() -> void:
	# Se elige el lado del muro por el que rodear, el que más se acerca a la
	# meta, y se mantiene esa preferencia un rato para no dublar entre los dos
	# lados frame a frame.
	_borde = Vector2.ZERO
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if not (col.get_collider() is StaticBody2D):
			continue
		var lado := col.get_normal().orthogonal().normalized()
		if lado.dot(_meta - global_position) < 0.0:
			lado = -lado
		_borde = lado
		break
	if _borde == Vector2.ZERO:
		_borde = Vector2.from_angle(randf() * TAU)
	_borde_t = desatasque_tiempo
	print("[enemigo] atascado en ", global_position, ", bordea por el lado ", _borde)


# Si ya está en el final de la ruta es que la meta cae donde no se puede
# llegar, no que se haya quedado prensado: no hay muro del que freeing.
func _en_el_final_de_la_ruta() -> bool:
	if _agente == null:
		return true
	return _agente.is_navigation_finished()


func _frenar(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, frenado * delta)
	move_and_slide()
	_bloqueado = false


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


# La meta se sortea dentro de la pantalla, pero el pasillo está excavado en la
# malla y los sorteos caen dentro de los muros. Se proyecta cada intento sobre
# la malla y se descarta el que acabe dentro de un muro.
func _punto_aleatorio() -> Vector2:
	var area := get_viewport_rect().grow(-margen)
	for intento in 24:
		var cand := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y)
		)
		var en_malla := _en_malla(cand)
		if not en_malla.is_finite():
			continue
		if not _cuerpo_libre(en_malla):
			continue
		return en_malla
	return global_position


# Medio ancho del cuerpo: lo que hay que dejar de margen respecto a los muros.
# Se mide la forma YA escalada, porque el nodo tiene scale 0.7 para que quepa
# por los pasillos de un tile: sin esto, la sonda mediría el cuerpo en grande y
# el enemigo se negaría a meterse por los pasillos que sí caben.
func _medio_cuerpo() -> float:
	var forma := _cuerpo.shape
	var lado := 32.0
	if forma is RectangleShape2D:
		lado = (forma as RectangleShape2D).size.length() * 0.25
	elif forma is CircleShape2D:
		lado = (forma as CircleShape2D).radius
	return lado * maxf(global_scale.x, global_scale.y)
