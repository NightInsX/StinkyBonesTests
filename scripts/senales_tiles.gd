class_name SenalesTiles
extends Node2D

# Señal booleana por celda del mapa: cada suelo tiene un interruptor que pasa de
# false a true cuando una onda de la Girl lo alcanza, y se queda en true.
#
# Se guarda como un PackedByteArray con una entrada por celda en vez de un nodo
# por celda: un mapa de 25x25 son 625 celdas, y 625 nodos sólo para tener un
# booleano sería absurdo. Quien quiera enterarse de un cambio se conecta a la
# señal `celda_marcada`.
#
# La onda atraviesa los muros, porque así funciona en el resto del juego: el
# enemigo oye por radio y no le mira la línea de visión. Por eso esto revela el
# cono entero, no sólo lo que hay a la vista. Si algún dia se quiere que la onda
# no atraviese las paredes, el sitio es `_marcar_celda()`: basta con comprobar
# que la celda está conectada con el origen de la onda.

## Capa de colisión de la que se leen las ondas. Por defecto sólo las de la Girl:
## las del enemigo no develan el mapa.
@export_flags_2d_physics var capas_onda: int = Echo.CAPA_ONDA_JUGADORA
@export var nodo_mapa: NodePath = ^".."

## Emite al pasar una celda de false a true. Con la posición ya en celdas, que es
## lo que se necesita para dibujar o para preguntar al mapa.
signal celda_marcada(celda: Vector2i)
## Emite cuando ya no queda ninguna celda por marcar, una sola vez por ronda.
signal mapa_revelado

var _mapa: DTLMapa = null
var _bandas: PackedByteArray = PackedByteArray()
var _ancho: int = 0
var _alto: int = 0
var _quedan: int = 0
var _revelado: bool = false


func _ready() -> void:
	_mapa = get_node_or_null(nodo_mapa) as DTLMapa
	if _mapa == null:
		push_warning("SenalesTiles: no encuentro el mapa en '%s'." % nodo_mapa)
		set_process(false)
		return
	_reservar()
	_mapa.generar_terminada.connect(_reservar)


func _process(_delta: float) -> void:
	# Las ondas duran menos de un segundo, así que basta con mirarlas cada frame:
	# no hay que guardar ninguna lista propia, se le pregunta al grupo.
	for nodo in get_tree().get_nodes_in_group(Echo.FUENTE_GROUP):
		var onda := nodo as Echo
		if onda == null or not is_instance_valid(onda):
			continue
		if not (capas_onda & onda.capa):
			continue
		_marcar_cono(onda)


# ---------------------------------------------------------------- consulta

## Estado de la señal de una celda. False para celdas fuera del mapa o de muro:
## un muro no se revela porque no hay nada que revelar.
func senal_de(celda: Vector2i) -> bool:
	if not _dentro(celda):
		return false
	return _bandas[celda.y * _ancho + celda.x] != 0


## Todas las celdas con señal. Sirve para, por ejemplo, dibujar el mapa revelado.
func celdas_con_senal() -> Array[Vector2i]:
	var salida: Array[Vector2i] = []
	for y in _alto:
		for x in _ancho:
			var celda := Vector2i(x, y)
			if senal_de(celda):
				salida.append(celda)
	return salida


## Cuántas celdas de suelo quedan sin revelar. El mapa entero da el total: se
## cuentan al reservar, así que ir restando sobre `celdas_reveladas` sería igual
## de fácil pero sólo válido si el mapa no se regenera por medio.
func quedan_por_revelar() -> int:
	return _quedan


func revelado() -> bool:
	return _revelado


## Vuelve a dejar todas las señales en false, como si la partida empezara.
func reiniciar() -> void:
	_reservar()


# ---------------------------------------------------------------- marcado

func _marcar_celda(celda: Vector2i) -> void:
	if not _dentro(celda) or not _mapa.es_transitable(celda):
		return
	var i := celda.y * _ancho + celda.x
	if _bandas[i] != 0:
		return
	_bandas[i] = 1
	_quedan -= 1
	celda_marcada.emit(celda)
	if _quedan <= 0 and not _revelado:
		_revelado = true
		mapa_revelado.emit()


## Marca las celdas que cubre el cono de una onda ahora mismo. Se recorre sólo el
## rectángulo que la envuelve, y se descartan las celdas ya marcadas, así que
## repetir cada frame sobre la misma onda no cuesta más que un vistazo.
func _marcar_cono(onda: Echo) -> void:
	if _ancho == 0:
		return
	var radio := onda.radio_actual()
	if radio <= 0.0:
		return

	var centro := _mapa.celda_de(onda.global_position)
	var alcance := int(ceil(radio / float(_mapa.tile))) + 1
	var medio := deg_to_rad(onda.angulo) * 0.5

	for dy in range(-alcance, alcance + 1):
		for dx in range(-alcance, alcance + 1):
			var celda := centro + Vector2i(dx, dy)
			if not _dentro(celda):
				continue
			if _bandas[celda.y * _ancho + celda.x] != 0:
				continue
			if not _en_cono(_mapa.centro_celda(celda), onda.global_position,
					onda.global_rotation, radio, medio):
				continue
			_marcar_celda(celda)


## ¿El punto cae dentro del sector? Se pasa a coordenadas locales de la onda y se
## mira que esté por delante, dentro del radio y dentro de la apertura.
func _en_cono(punto: Vector2, origen: Vector2, giro: float, radio: float,
		medio: float) -> bool:
	var local := (punto - origen).rotated(-giro)
	if local.x < 0.0 or local.length() > radio:
		return false
	return absf(local.angle()) <= medio


func _reservar(_dimensiones: Vector2i = Vector2i.ZERO) -> void:
	if _mapa == null:
		return
	var d := _mapa.dimensiones()
	_ancho = d.x
	_alto = d.y
	if _ancho <= 0 or _alto <= 0:
		_bandas = PackedByteArray()
		_quedan = 0
		return
	_bandas.resize(_ancho * _alto)
	_bandas.fill(0)
	_revelado = false
	# Sólo cuenta el suelo: los muros no se revelan nunca.
	var suelo := 0
	for y in _alto:
		for x in _ancho:
			if _mapa.es_transitable(Vector2i(x, y)):
				suelo += 1
	_quedan = suelo


func _dentro(celda: Vector2i) -> bool:
	return celda.x >= 0 and celda.y >= 0 and celda.x < _ancho and celda.y < _alto
