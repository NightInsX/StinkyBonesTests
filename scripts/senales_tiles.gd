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
# La onda YA no atraviesa los muros: la de la Girl muere al tocar el primero
# (ver Echo._ready), así que lo que se revela es lo que el sonido alcanza de
# verdad, con línea de visión. Eso hace que este archivo no tenga que comprobar
# ninguna pared: si una celda sale marcada, la onda llegó de verdad hasta ella.
# Si algún dia se quisiera una onda que sí atraviese (una onda a través del muro, o
# el radio de sondeo del enemigo), el sitio sigue siendo `_marcar_celda()`: basta
# con que no se descarte lo que haya al otro lado.

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


## Marca las celdas que cubre el cono de una onda ahora mismo. Se recorre la
## parte del cuadrado que la envuelve que el cono cruza, fila a fila, y se
## descartan las celdas ya marcadas, así que repetir cada frame sobre la misma
## onda no cuesta más que un vistazo.
##
## El radio sale de `radio_en_direccion()` y no del de la onda entera: la onda
## viene recortada contra los muros, así que un único radio sería mayor que lo
## que suena en la mayoría de las direcciones y marcaría como vistas celdas que
## están detrás de un muro.
func _marcar_cono(onda: Echo) -> void:
	if _ancho == 0:
		return
	var radio := onda.radio_actual()
	if radio <= 0.0:
		return

	var centro := _mapa.celda_de(onda.global_position)
	var alcance := int(ceil(radio / float(_mapa.tile))) + 1

	# Lo que no cambia dentro del bucle se calcula aquí, una vez por onda y por
	# frame: el centro del cono en el mundo, el paso de una celda a la siguiente
	# (con la base del mapa, por si algún día se gira o se escala) y el giro de la
	# onda guardado en seno y coseno.
	#
	# Antes cada celda pagaba `_mapa.centro_celda()`, que son tres llamadas
	# encadenadas (centro_celda -> _centro_celda -> to_global), más el `alcanza()`
	# con sus tres internas. En un mapa de 51x51 con dos ondas en el aire eran
	# cientos de miles de llamadas por segundo para descartar casi todas las
	# celdas: sólo el marcado llegaba a costar más que el resto del juego entero.
	var base := _mapa.centro_celda(centro)
	var mapa_tf := _mapa.global_transform
	var paso_x := mapa_tf.x * float(_mapa.tile)
	var paso_y := mapa_tf.y * float(_mapa.tile)

	var origen := onda.global_position
	var giro := -onda.global_rotation
	var coseno := cos(giro)
	var seno := sin(giro)

	var x0 := centro.x
	var y0 := centro.y

	# La celda (dx, dy) vista desde la onda sale de dos expresiones lineales:
	#   lx = a.x*dx + b.x*dy + o.x     ly = a.y*dx + b.y*dy + o.y
	# con `a` = R^-1·paso_x, `b` = R^-1·paso_y y `o` = R^-1·(centro - origen), o
	# sea lo mismo que calcula el bucle de ahí abajo, despiezado por columnas. El
	# cono (lx >= 0 y |ly| <= lx*tan(mitad)) cruza cada fila en un tramo CONTIGUO
	# de dx, así que para cada fila se estrecha ese tramo y sólo se recorre él.
	#
	# Sin esto se barre el cuadrado entero: para un radio de 11 tiles son 625
	# celdas y el cono son unas 60, o sea diez veces más llamadas a
	# `alcanza_local()` de las necesarias, y esa era la partida de proceso más
	# grande que quedaba (~1.2 ms por frame con una onda en el aire).
	var mitad := deg_to_rad(onda.angulo) * 0.5
	var tangente := tan(mitad)
	var ax := coseno * paso_x.x - seno * paso_x.y
	var ay := seno * paso_x.x + coseno * paso_x.y
	var bx := coseno * paso_y.x - seno * paso_y.y
	var by := seno * paso_y.x + coseno * paso_y.y
	var centro_dx := base.x - origen.x
	var centro_dy := base.y - origen.y
	var ox := coseno * centro_dx - seno * centro_dy
	var oy := seno * centro_dx + coseno * centro_dy

	for dy in range(-alcance, alcance + 1):
		var y := y0 + dy
		if y < 0 or y >= _alto:
			continue
		var fila := y * _ancho
		var qx := bx * dy + ox
		var qy := by * dy + oy
		# Los tres bordes del cono, cada uno como p*dx + q >= 0: el eje del cono
		# (lx >= 0) y las dos bisectrices (|ly| <= lx*tan(mitad)). `qx` y `qy` son
		# lx y ly de esta fila para dx = 0, o sea lo que queda fuera del término
		# en dx.
		var rango := Vector2i(-alcance, alcance)
		rango = _estrechar_recta(ax, qx, rango)
		rango = _estrechar_recta(ax * tangente - ay, qx * tangente - qy, rango)
		rango = _estrechar_recta(ax * tangente + ay, qx * tangente + qy, rango)
		if rango.x > rango.y:
			continue
		# Delta mundo - origen de la onda para la fila entera; dentro del bucle
		# sólo se le suma lo que falta en X.
		var oy_fila := base.y + paso_y.y * dy - origen.y
		var ox_fila := base.x + paso_y.x * dy - origen.x
		for dx in range(rango.x, rango.y + 1):
			var x := x0 + dx
			if x < 0 or x >= _ancho:
				continue
			var i := fila + x
			if _bandas[i] != 0:
				continue
			var dxm := ox_fila + paso_x.x * dx
			var dym := oy_fila + paso_x.y * dx
			# El mismo giro que hace Echo.alcanza() con .rotated(-rotación).
			var lx := dxm * coseno - dym * seno
			var ly := dxm * seno + dym * coseno
			if not onda.alcanza_local(lx, ly):
				continue
			_marcar_celda(Vector2i(x, y))


## Estrecha `rango` con la recta p*dx + q >= 0, que es el recorte que hace un
## borde del cono sobre una fila. Si la recta no deja nada en la fila, devuelve
## un rango vacío (x > y).
##
## Se añade un peldaño de holgura a cada lado: los bordes del cono se resuelven
## con aritmética de coma flotante y un redondeo de más comería una celda que
## `alcanza_local()` sí acepta. La de sobra la descarta la llamada, que es barata.
func _estrechar_recta(p: float, q: float, rango: Vector2i) -> Vector2i:
	if p > 0.0:
		return Vector2i(maxi(rango.x, ceili(-q / p) - 1), rango.y)
	if p < 0.0:
		return Vector2i(rango.x, mini(rango.y, floori(-q / p) + 1))
	if q < 0.0:
		return Vector2i(rango.y + 1, rango.y)
	return rango



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
