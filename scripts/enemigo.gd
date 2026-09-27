class_name Enemigo
extends CharacterBody2D

const Ecolocalización = preload("res://scenes/echo.tscn")

## Grupo en el que se apunta al entrar, para que la Girl pueda avisarlo sin
## conocer su ruta ni su nombre en el árbol. El nombre es la constante, no un
## literal suelto en cada script.
const GRUPO := &"enemigo"

@export var velocidad_max: float = 300
@export var aceleracion: float = 900.0
@export var frenado: float = 900.0
@export var llegada: float = 12.0  # distancia a la que se considera que ha llegado
@export var pausa_min: float = 0.3  # segundos parado entre destino y destino
@export var pausa_max: float = 1
@export var margen: float = 160.0  # no se acerca a los bordes del mapa

@export_group("Oído")
@export var onda_max_radius: float = 400.0
@export var onda_duration: float = 0.7
@export var onda_intervalo: float = 1.6  # media entre ondas y ondas
@export var distancia_carga: float = 1800.0  # si la oye más cerca de esto, va a por ella
@export var memoria_segundos: float = 8.0  # cuánto recuerda dónde la oyó
@export var radio_busqueda: int = 5  # celdas que barre alrededor del punto oído

@export_group("Bloque sensible")
## Segundos que persigue el golpe de la Girl contra un bloque sensible. Se
## aparta de `memoria_segundos` a propósito: la onda se atenúa con la distancia
## y con los muros de por medio, pero el golpe es una pista directa que llega
## desde la otra punta del mapa, así que merece más tiempo.
@export var alerta_segundos: float = 15.0

@export_group("Desatasco")
## Segundos sin avanzar de verdad antes de buscar salida. Antes sólo miraba si
## chocaba en ESTE frame, y eso no distingue entre rozar una esquina y estar
## empotrado en un pasillo, así que disparaba el rodeo antes de tiempo.
@export var sin_avance_max: float = 1.2
@export var desatasque_tiempo: float = 0.9  # segundos que dura la decision de bordear
@export var paso_rodeo: float = 200.0  # hasta donde prueba un rodeo antes de rendirse
@export var ajuste_malla: float = 40.0  # margen para aceptar un punto casi fuera de la malla
@export var capas_muro: int = 1  # capas de física que cuentan como muro infranqueable

@export_group("Aparición cada X tiempo")
## Cada estos segundos el enemigo reaparece en una sala cerca de la jugadora, para
## que la partida no se eternice con el enemigo perdido en la otra punta del mapa.
## Ponerlo a 0 lo desactiva.
@export var intervalo_caceria: float = 300.0
@export var radio_caceria: int = 7  # celdas: radio de aparición alrededor de ella
## Celdas mínimas (distancia de Chebyshev) que tienen que separarle de la
## jugadora al aparecer. Es innegociable: se exige en TODAS las rondas de
## búsqueda, y si no hay ninguna celda que lo cumpla, no aparece. Con 4 celdas
## las zonas de muerte no llegan a solaparse, así que la partida nunca se acaba
## en el mismo instante de la aparición.
@export var radio_caceria_min: int = 4

@export_group("Referencias")
@export var nodo_jugadora: NodePath = ^"../girl"
@export var nodo_mapa: NodePath = ^"../MapaDTL"

@onready var _oido: Area2D = $Oido
@onready var _agente: NavigationAgent2D = $Agente
@onready var _cuerpo: CollisionShape2D = $CollisionShape2D

var _destino: Vector2 = Vector2.ZERO
var _pausa: float = 0.0
var _espera_onda: float = 0.0
var _memoria: float = 0.0
var _ultima_onda_pos: Vector2 = Vector2.ZERO
## true mientras la pista que sigue es un GOLPE contra un bloque sensible y no
## un sonido. Un golpe es un aviso directo: la Girl está ahí, pegada al muro, y
## hay que ir aunque esté más lejos de `distancia_carga`. Se apaga solo cuando
## se acaba `alerta_segundos` o cuando vuelve a oír una onda, que ya es pista
## propia.
var _alerta: bool = false
## Segundos que quedan de persecución por el golpe, o 0 si no hay alerta.
var _alerta_restante: float = 0.0

## Ondas que han solapado con el `Oido` y a las que aún no se ha decidido si se
## oyen. Sin tipar a propósito: una `Array[Echo]` con una onda ya liberada peta al
## validarla, y las ondas se borran solas al terminar.
var _ondas_oido: Array = []

var _pos_previa: Vector2 = Vector2.ZERO
var _atascado: float = 0.0
var _ruta_impresa: bool = false

# Estado del desatasque.
var _meta: Vector2 = Vector2.ZERO  # a dónde va ahora mismo, sea carga o paseo
var _bloqueado: bool = false  # este frame ha chocado con un muro de frente
var _borde: Vector2 = Vector2.ZERO  # lado del muro que se decide a bordear
var _borde_t: float = 0.0
var _radio: float = 32.0  # paso de muestreo al medir el cuerpo
var _sonda: Shape2D
var _espacio: PhysicsDirectSpaceState2D

# Desatasco en tres escalones: primero rodea el muro, luego retrocede por donde
# ha venido y, si tampoco, se va a cualquier sitio alcanzable a nearby. Con un
# solo escalón se quedaba encallado: el rodeo lo devolvía al mismo punto y
# vuelta a empezar.
var _nivel_atasco: int = 0
var _sin_avance: float = 0.0
var _fuga: Vector2 = Vector2.ZERO
var _fuga_t: float = 0.0

# ¿Está barriendo la zona donde la oyó en vez de yendo a por ella?
var _barriendo: bool = false
var _destino_barrido: Vector2 = Vector2.ZERO

var _caceria: float = 0.0
var _jugadora: Node2D = null
var _mapa: DTLMapa = null

# Direcciones que se prueban como rodeo, de menos a más apartada del objetivo.
const _RODEOS := [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6, 2.0, -2.0, PI]


func _ready() -> void:
	_radio = _medio_cuerpo()
	_preparar_sonda()
	_pos_previa = global_position
	add_to_group(GRUPO)
	# Que no dispare en el mismo instante que la Girl, para no solaparse.
	_espera_onda = randf_range(0.4, onda_intervalo)
	_jugadora = get_node_or_null(nodo_jugadora) as Node2D
	_mapa = get_node_or_null(nodo_mapa) as DTLMapa
	_caceria = intervalo_caceria
	# Oye las ondas de la Girl; las suyas van en otra capa, así que no se
	# oye a sí mismo.
	if _oido == null:
		push_warning("scripts/enemigo.gd: falta el Area2D hijo 'Oido', no oirá a la Girl")
	else:
		_oido.collision_mask = Echo.CAPA_ONDA_JUGADORA
		_oido.area_entered.connect(_on_onda_entrada)
		_oido.area_exited.connect(_on_onda_salida)
	# La malla se puede generar al cargar la escena y tarda un frame en
	# sincronizarse, así que la primera meta se sortea con la malla ya en pie.
	await get_tree().physics_frame
	_destino = _punto_aleatorio()
	print("[enemigo] primera meta ", _destino)


func _physics_process(delta: float) -> void:
	_espacio = get_world_2d().direct_space_state
	_gastar_memoria(delta)
	_oír_ondas()
	_moverse(delta)
	_lanzar_onda(delta)
	_contar_caceria(delta)



func _on_onda_entrada(area: Area2D) -> void:
	if not area.is_in_group(Echo.AREA_GROUP):
		return
	var onda := area.get_parent() as Echo
	if onda == null:
		return
	# La onda sólo se apunta aquí; si se oye, se mira en `_oír_ondas()`, cada
	# frame.
	#
	# Antes se decidía en este momento y medido sonaba en 9 de 40 casos con la Girl
	# a un tile y medio y a la vista: `area_entered` salta en el primer frame de
	# vida de la onda, y ahí el radio todavía vale cero y el recorte contra los
	# muros aún no está calculado, así que `alcanza()` contestaba que no y el
	# enemigo se quedaba sordo para siempre. Y como la forma de colección nace
	# con el radio entero, el solape empieza en el frame 0 y el signal no vuelve a
	# saltar cuando el sonido llega de verdad.
	if not _ondas_oido.has(onda):
		_ondas_oido.append(onda)


## La onda se va del `Oido`: se suelta de la lista en vez de esperar a que
## `_oír_ondas()` la encuentre liberada.
func _on_onda_salida(area: Area2D) -> void:
	if not area.is_in_group(Echo.AREA_GROUP):
		return
	var onda := area.get_parent() as Echo
	if onda == null:
		return
	_ondas_oido.erase(onda)


## La Girl ha chocado contra un bloque sensible: la llaman desde
## `character_body_2d.gd` con el punto exacto del golpe. Va directo a por él,
## sin comprobar distancia (`_alerta`), porque un muro que se queja es una
## pista mejor que un sonido: dice dónde está ella y además está atascada
## un rato contra ese muro.
func alertar(punto: Vector2) -> void:
	_ultima_onda_pos = punto
	_memoria = memoria_segundos
	_alerta = true
	_alerta_restante = alerta_segundos
	_barriendo = false
	_pausa = 0.0
	_fuga_t = 0.0
	_ruta_impresa = false
	print("[enemigo] ALERTA: golpe contra un bloque sensible en ", punto,
			" a ", int(global_position.distance_to(punto)), " px")


## ¿Ha llegado el sonido de alguna de las ondas que ha solapado con el Oido?
## Se mira cada frame porque la onda crece: la que nace lejos sólo cuenta cuando
## su frente pasa por aquí, y ese momento no avisa la física con ningún signal.
func _oír_ondas() -> void:
	if _ondas_oido.is_empty():
		return
	var siguen: Array = []
	for onda in _ondas_oido:
		# Las ondas se borran solas al terminar, y sin esta comprobación una onda
		# liberada deja la lista con un cuerpo muerto dentro.
		if not is_instance_valid(onda) or not onda.is_inside_tree():
			continue
		# El Oido es un círculo de `radio_oido`, enorme, y asoma por detrás de los
		# muros y por fuera del cono, así que el solape que le avisa la física no
		# basta: sólo cuenta si el enemigo está donde la onda llega de verdad, y si
		# hay línea de visión hasta la Girl. Medido sin esto: oía a través de los
		# muros en 15 de 15 casos; con esto, en ninguno.
		if not onda.alcanza(global_position):
			siguen.append(onda)
			continue
		if not _llega_el_sonido(onda):
			siguen.append(onda)
			continue
		_ultima_onda_pos = onda.global_position
		_memoria = memoria_segundos
		# Oída de verdad: la onda manda sobre un golpe anterior, que ya no aporta.
		_alerta = false
		_alerta_restante = 0.0
		print("[enemigo] OÍDO: Girl en ", _ultima_onda_pos,
			" dist=", global_position.distance_to(_ultima_onda_pos),
			" recuerda ", memoria_segundos, "s")
		# Oída: no se sigue con esta onda, y se sueltan las que quedaran.
		_ondas_oido = siguen
		return
	_ondas_oido = siguen


## ¿Se ve a la Girl desde aquí? Tres rayos contra la capa de los muros: si no hay
## nada entre medias, el sonido ha podido llegar, y si hay pared, no. Se dispara
## contra la Girl y no contra el borde de la onda porque el sonido sale de ella.
func _llega_el_sonido(onda: Echo) -> bool:
	if _espacio == null:
		_espacio = get_world_2d().direct_space_state
	if _espacio == null:
		return true
	# Tres rayos, el del medio y dos desplazados de lado, y tienen que estar los
	# tres limpios. Con uno solo pasaba lo de siempre: un rayo que va pegado a la
	# arista de un muro lo cuenta como golpe, y a un pelo de lado ya no, así que
	# de vez en cuando el enemigo oía a través de una esquina. Medido: 1 de 27
	# casos con muro de por medio. La perpendicular va hacia el lado que más
	# cosas tapa, para no perder oído de más en un pasillo estrecho.
	var linea := onda.global_position - global_position
	var lado := linea.orthogonal().normalized() * 6.0
	var origenes := [Vector2.ZERO, lado, -lado]
	for desplazamiento in origenes:
		var q := PhysicsRayQueryParameters2D.create(global_position + desplazamiento,
				onda.global_position)
		q.collision_mask = Bloque.CAPA_MURO
		q.collide_with_areas = false
		q.collide_with_bodies = true
		if not _espacio.intersect_ray(q).is_empty():
			return false
	return true


func _gastar_memoria(delta: float) -> void:
	# La alerta de un golpe tiene reloj propio: mientras dura, la memoria de la
	# onda no se gasta, porque ésta está pensada para un sonido que se desvanece
	# con la distancia y la alerta no.
	if _alerta:
		_alerta_restante -= delta
		if _alerta_restante > 0.0:
			return
		_alerta = false
		_alerta_restante = 0.0
		_memoria = 0.0
		_ruta_impresa = false
		print("[enemigo] se le ha pasado la ALERTA: vuelve a pasearse")
		return
	if _memoria <= 0.0:
		return
	_memoria -= delta
	if _memoria <= 0.0:
		_memoria = 0.0
		_ruta_impresa = false
		print("[enemigo] se le ha pasado: vuelve a pasearse")


# Carga contra el punto que oyó, si aún lo recuerda y no está demasiado lejos.
# La excepción es la alerta de un golpe contra bloque sensible: esa va siempre,
# porque el sonido se atenúa con la distancia y el golpe no.
func _cargando() -> bool:
	if _alerta:
		return true
	if _memoria <= 0.0:
		return false
	return global_position.distance_to(_ultima_onda_pos) < distancia_carga


func _moverse(delta: float) -> void:
	# Cargar tiene prioridad: si no, el enemigo se pasea sin enterarse.
	if _cargando():
		if global_position.distance_to(_ultima_onda_pos) > llegada:
			_barriendo = false
			_ir_a(_ultima_onda_pos, delta)
			return
		# Ha llegado a donde la oyó, pero aún lo recuerda. Antes se paraba ahí
		# clavado hasta que se le olvidaba, y con la carga teniendo prioridad
		# no volvía a moverse: eran 8 s de parón a la vista de la jugadora.
		# Ahora barre la zona, que es donde más opciones tiene de oírla otra vez.
		if not _barriendo:
			_barriendo = true
			_destino_barrido = _punto_cerca(_ultima_onda_pos, radio_busqueda)
		if global_position.distance_to(_destino_barrido) <= llegada:
			_destino_barrido = _punto_cerca(_ultima_onda_pos, radio_busqueda)
			_frenar(delta)
			return
		_ir_a(_destino_barrido, delta)
		return

	_barriendo = false
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
	_fuga_t = maxf(_fuga_t - delta, 0.0)

	# Mientras huye ignora la ruta: viene de ahí, así que se conoce libre, y
	# ninguna ruta va a sacarlo de un sitio donde la ruta ya lo ha metido.
	var siguiente := _fuga if _fuga_t > 0.0 else _destino_libre(_waypoint(_meta))
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


# La sonda tiene que ser la FORMA REAL del cuerpo, no un círculo con su medio
# ancho. El cuerpo es un cuadrado de 92x92: 46 px de semilado en los ejes y 65
# en las diagonales. Midiendo con un círculo de 32 px, la sonda daba el visto
# bueno a esquiños por los que el cuadrado no cabe: el enemigo se metía, se
# encallaba, y el rodeo lo devolvía al mismo sitio una y otra vez. Ése era el
# bucle de "atascado" que se veía en consola.
func _preparar_sonda() -> void:
	var original := _cuerpo.shape
	if original == null:
		_sonda = CircleShape2D.new()
		_sonda.radius = _radio
		return
	_sonda = original.duplicate() as Shape2D
	var s := maxf(global_scale.x, global_scale.y)
	if _sonda is RectangleShape2D:
		(_sonda as RectangleShape2D).size *= s
	elif _sonda is CircleShape2D:
		(_sonda as CircleShape2D).radius *= s


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


# Cuando el enemigo lleva un rato sin avanzar de verdad, hay que buscar salida.
# Antes sólo miraba si chocaba en ESTE frame, y como el waypoint cambia cada
# frame eso no distinguía entre rozar una esquina y estar empotrado, así que el
# rodeo saltaba antes de tiempo y se quedaba con la meta imposible. Ahora se
# mide avance real sobre una ventana de `sin_avance_max` segundos y la salida se
# escala en tres escalones, porque bordear un muro sólo funciona si el rodeo
# acaba pasando por un hueco: si no, hay que deshacer el camino hecho.
func _vigilar_atasco(delta: float) -> void:
	var avanzando := global_position.distance_to(_pos_previa) > velocidad_max * delta * 0.5
	_pos_previa = global_position

	if _bloqueado or (not avanzando and not _en_el_final_de_la_ruta()):
		_atascado += delta
		_sin_avance += delta
	else:
		_atascado = 0.0
		_sin_avance = 0.0
		_nivel_atasco = 0

	if _sin_avance < sin_avance_max:
		return
	_sin_avance = 0.0
	_atascado = 0.0
	_desatascar()


func _desatascar() -> void:
	_nivel_atasco += 1
	match _nivel_atasco:
		1:
			_rodear_muro()
		2:
			_retroceder()
		_:
			_esquivar()


# Primer escalón: elegir el lado del muro por el que rodear, el que más se
# acerca a la meta, y mantener esa preferencia un rato para no dublar entre los
# dos lados frame a frame.
func _rodear_muro() -> void:
	_borde = _dir_bloqueo().orthogonal().normalized()
	if _borde.dot(_meta - global_position) < 0.0:
		_borde = -_borde
	if _borde == Vector2.ZERO:
		_borde = Vector2.from_angle(randf() * TAU)
	_borde_t = desatasque_tiempo
	print("[enemigo] encallado en ", global_position, ", bordea por ", _borde)


# Segundo escalón: deshacer el camino. Si lleva un rato sin avanzar es que la
# dirección que tomaba era mala, así que va para atrás, que es terreno que ya
# ha recorrido y por tanto libre.
func _retroceder() -> void:
	var dir := _dir_bloqueo()
	if dir == Vector2.ZERO:
		dir = (global_position - _meta).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(randf() * TAU)
	_fuga = _en_malla_o_si(global_position - dir * paso_rodeo, global_position)
	_fuga_t = desatasque_tiempo
	print("[enemigo] no sale, retrocede a ", _fuga)


# Último escalón: se rinde con la dirección actual y se va a cualquier sitio
# alcanzable cerca. Si tampoco así se mueve, es que ya no hay destino posible y
# lo único que queda es olvidarse de la pista y volver a estudiar el mapa.
func _esquivar() -> void:
	_nivel_atasco = 0
	var meta := _punto_cerca(global_position, 4)
	if meta.distance_to(global_position) < 1.0:
		_memoria = 0.0
		# Rendición total: si siguiera con la alerta volvería a cargar contra el
		# mismo punto imposible y el bucle de atasco no acabaría nunca.
		_alerta = false
		_alerta_restante = 0.0
		_destino = _punto_aleatorio()
		print("[enemigo] atascado de verdad, abandona la pista")
		return
	_fuga = meta
	_fuga_t = desatasque_tiempo
	print("[enemigo] se desvía a ", meta)


# Dirección de salida del muro que tiene delante, o Vector2.ZERO si no hay
# ninguno. Se usa tanto para elegir el lado del rodeo como para retroceder.
func _dir_bloqueo() -> Vector2:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if not (col.get_collider() is StaticBody2D):
			continue
		if col.get_normal().dot(velocity) >= 0.0:
			continue
		return col.get_normal()
	return Vector2.ZERO


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


# ---------------------------------------------------------------- apariciones

# Cada `intervalo_caceria` segundos el enemigo reaparece cerca de la jugadora.
# Es la red de seguridad de la partida: por muy bien que vaya el hide and seek,
# a los 5 minutos tiene que haber siempre un enfrentamiento, o si no se
# convierte en un paseo por un mapa vacío.
func _contar_caceria(delta: float) -> void:
	if intervalo_caceria <= 0.0:
		return
	_caceria -= delta
	if _caceria > 0.0:
		return
	_caceria = intervalo_caceria
	_cazar()


func _cazar() -> void:
	if _jugadora == null or _mapa == null:
		return
	var celda := _celda_sala_cerca(_jugadora.global_position)
	if celda.x < 0:
		push_warning("scripts/enemigo.gd: no hay ninguna sala donde aparecer.")
		return
	_aparecer(_mapa.centro_celda(celda))


# Busca una celda donde aparecer alrededor de la jugadora. Se va aflojando una
# condición cada ronda, en este orden, porque la aparición tiene que ser SIEMPRE
# lejos de ella: lo único que se relaja es el tipo de sitio, nunca la distancia.
#
#   1) sala de verdad, a un radio cómodo
#   2) sala de verdad, radio doble
#   3) sala de verdad, en todo el mapa
#   4) cualquier celda transitable, por si el mapa no tiene ni una sala de 3x3
#
# Todas las rondas piden como mínimo `radio_caceria_min` celdas de distancia:
# antes se aflojaba a 0 en las rondas de reserva y el enemigo podía caer en la
# misma celda que la jugadora, lo que terminaba la partida al instante. Si en
# todo el mapa no hay ninguna celda a esa distancia (mapa minúsculo), se
# devuelve Vector2i(-1,-1) y no se aparece: mejor eso que perder la partida.
func _celda_sala_cerca(centro: Vector2) -> Vector2i:
	var base := _mapa.celda_de(centro)
	var limite := maxi(_mapa.dimensiones().x, _mapa.dimensiones().y)
	var minimo := distancia_minima()
	var radio := clampi(maxi(radio_caceria, minimo), 2, maxi(limite, 2))

	var celda := _mapa.celda_sala_cerca(base, radio, minimo, 1)
	if celda.x >= 0:
		return celda

	# Radio doble, pero sigue sin poder acercarse de más.
	celda = _mapa.celda_sala_cerca(base, mini(radio * 2, limite), minimo, 1)
	if celda.x >= 0:
		return celda

	# Toda la superficie del mapa.
	celda = _mapa.celda_sala_cerca(base, limite, minimo, 1)
	if celda.x >= 0:
		return celda

	return _mapa.celda_sala_cerca(base, limite, minimo, 0)


## Distancia mínima exigida a la jugadora, en celdas.
func distancia_minima() -> int:
	return maxi(radio_caceria_min, 1)


# Teletransporte a una celda de sala. Se limpia todo el estado de atasco porque
# la posición cambia de golpe, y se le da la posición de la jugadora como si la
# hubiera oído: para eso aparece tan cerca.
func _aparecer(destino: Vector2) -> void:
	if not _destino_valido(destino):
		return
	global_position = destino
	velocity = Vector2.ZERO
	_atascado = 0.0
	_sin_avance = 0.0
	_nivel_atasco = 0
	_fuga_t = 0.0
	_barriendo = false
	_pausa = 0.0
	_destino = destino
	_destino_barrido = destino
	_alerta = false
	_alerta_restante = 0.0
	if _jugadora != null:
		_ultima_onda_pos = _jugadora.global_position
	_memoria = memoria_segundos
	var dist_px := -1
	if _jugadora != null:
		dist_px = int(global_position.distance_to(_jugadora.global_position))
	print("[enemigo] CACERÍA: aparece en ", destino, " a ", dist_px, " px de la Girl")


## Filtro final antes de teletransportarse: si el destino no está a al menos
## `radio_caceria_min` celdas de la jugadora, no se aparece. Pase por donde
## pase la búsqueda, aquí no se cuela ninguna celda pegada a ella, así que el
## enemigo nunca puede salir encima de sus pies y matar la partida al instante.
func _destino_valido(destino: Vector2) -> bool:
	if _mapa == null or _jugadora == null:
		push_warning("scripts/enemigo.gd: sin mapa o sin jugadora, no se aparece.")
		return false
	var celda := _mapa.celda_de(destino)
	var suya := _mapa.celda_de(_jugadora.global_position)
	var dist := maxi(absi(celda.x - suya.x), absi(celda.y - suya.y))
	var minimo := distancia_minima()
	if dist >= minimo:
		return true
	push_warning("enemigo.gd: aparece a sólo %d celdas (mínimo %d)." % [dist, minimo])
	return false


# ---------------------------------------------------------------- puntos

# La meta se sortea dentro de la pantalla, pero el pasillo está excavado en la
# malla y los sorteos caen dentro de los muros. Se proyecta cada intento sobre
# la malla y se descarta el que acabe dentro de un muro.
func _punto_aleatorio() -> Vector2:
	return _punto_en(get_viewport_rect().grow(-margen))


# Punto alcanzable y libre a `celdas` celdas de `centro`, para barrer la zona
# donde se oyó algo o para salir de un atasco.
func _punto_cerca(centro: Vector2, celdas: int) -> Vector2:
	var lado := float(celdas) * _lado_celda()
	return _punto_en(Rect2(centro - Vector2(lado, lado), Vector2(lado, lado) * 2.0))


func _punto_en(area: Rect2) -> Vector2:
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


# Proyecta sobre la malla y, si el punto cae fuera, se queda con el de partida.
# Para los puntos de huida: mejor un sitio en la malla que uno en un muro.
func _en_malla_o_si(punto: Vector2, respaldo: Vector2) -> Vector2:
	var en_malla := _en_malla(punto)
	return respaldo if not en_malla.is_finite() else en_malla


# Lado de una celda del mapa, para poder hablar en celdas sin acoplar el
# enemigo al valor concreto de `tile`.
func _lado_celda() -> float:
	return float(_mapa.tile) if _mapa != null else 128.0


# Medio ancho del cuerpo: sólo se usa como paso de muestreo al medir si cabe.
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
