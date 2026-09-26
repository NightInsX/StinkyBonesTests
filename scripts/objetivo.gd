class_name Objetivo
extends Node

# Coloca la llave y la puerta de salida sobre el laberinto recién generado.
#
# Las distancias se miden en PASOS de celda por el suelo, no en línea recta. En un
# laberinto lo que cuesta es el camino, no la distancia: dos celdas separadas por
# una pared están pegadas y hay que rodearlas enteras.
#
# La puerta va en la celda transitable más lejana de donde aparece la jugadora, y
# la llave en un callejón sin salida del extremo opuesto. Con eso hay que recorrer
# el laberinto dos veces: una hasta la llave y otra hasta la salida, y no por el
# mismo camino.

@export var mapa: NodePath = NodePath("../MapaDTL")
@export var nodo_llave: NodePath = NodePath("../Llave")
@export var nodo_puerta: NodePath = NodePath("../Puerta")
@export var nodo_jugadora: NodePath = NodePath("../girl")
## La puerta no puede caer más cerca de la jugadora que esto. Avisa si no llega.
@export_range(0, 200) var distancia_minima_salida: int = 20
## Ni la llave. Es el otro lado del laberinto, así que se espera que dé.
@export_range(0, 200) var distancia_minima_llave: int = 15


func _ready() -> void:
	# Sin `await`, por el mismo motivo que MapaColocacion: DTLMapa ya ha generado
	# en su _enter_tree. Este nodo va después de ColocarEnMapa en la escena, así
	# que la jugadora ya está en su celda definitiva cuando esto corre.
	var destino := get_node_or_null(mapa) as DTLMapa
	if destino == null:
		push_warning("Objetivo: no encuentro el mapa en '%s'." % mapa)
		set_process(false)
		return

	colocar()
	destino.generar_terminada.connect(_al_regenerar)


func _al_regenerar(_dimensiones: Vector2i = Vector2i.ZERO) -> void:
	colocar()


## Recoloca llave y puerta y devuelve la partida a su estado inicial.
func colocar() -> void:
	var destino := get_node_or_null(mapa) as DTLMapa
	if destino == null or destino.dimensiones() == Vector2i.ZERO:
		return
	var salida := get_node_or_null(nodo_puerta) as Puerta
	var llave := get_node_or_null(nodo_llave) as Llave
	if salida == null or llave == null:
		push_warning("Objetivo: falta la puerta o la llave, no hay nada que colocar.")
		return

	var inicio := _celda_de_la_jugadora(destino)
	var pasos := _pasos_desde(destino, inicio)
	if pasos.is_empty():
		push_warning("Objetivo: el mapa no tiene suelo transitable desde ", inicio, ".")
		return

	var celda_salida := _celda_mas_lejana(destino, pasos)
	if celda_salida.x < 0:
		push_warning("Objetivo: no encuentro celda transitable para la salida.")
		return

	# La llave se mide desde la salida, no desde la jugadora: así queda en el
	# extremo opuesto a la puerta, que es donde había que ponerla.
	var desde_salida := _pasos_desde(destino, celda_salida)
	var celda_llave := _celda_callejon_opuesto(destino, desde_salida, pasos, celda_salida)

	salida.celda = celda_salida
	salida.reponer()
	salida.global_position = destino.centro_celda(celda_salida)

	llave.celda = celda_llave
	llave.reponer()
	llave.global_position = destino.centro_celda(celda_llave)

	var a_la_salida: int = pasos.get(celda_salida, -1)
	var a_la_llave: int = pasos.get(celda_llave, -1)
	if a_la_salida < distancia_minima_salida:
		push_warning("Objetivo: la salida sólo está a %d pasos; se pedían %d. "
				% [a_la_salida, distancia_minima_salida]
				+ "El laberinto ha salido demasiado pequeño.")
	if a_la_llave < distancia_minima_llave:
		push_warning("Objetivo: la llave sólo está a %d pasos; se pedían %d. "
				% [a_la_llave, distancia_minima_llave]
				+ "El laberinto ha salido demasiado pequeño.")
	print("[objetivo] salida en ", celda_salida, " (", a_la_salida,
			" pasos) | llave en ", celda_llave, " (", a_la_llave,
			" pasos de la jugadora, ", desde_salida.get(celda_llave, -1), " de la salida)")


# ---------------------------------------------------------------- colocación

## Dónde está la jugadora ahora mismo. Si por lo que sea su celda no es
## transitable (aparece antes de que la colocen, o quedó dentro de un muro), se
## recurre al centro de la región más amplia del mapa.
func _celda_de_la_jugadora(mapa: DTLMapa) -> Vector2i:
	var jugadora := get_node_or_null(nodo_jugadora) as Node2D
	if jugadora != null:
		var celda := mapa.celda_de(jugadora.global_position)
		if mapa.es_transitable(celda):
			return celda
	return mapa.celda_de(mapa.punto_inicial())


## Celda transitable a la que más pasos se llega. Entre las que empatan, la más
## pegada al borde del mapa, porque la salida tiene que parecer una salida y no
## un hueco en mitad de un pasillo.
func _celda_mas_lejana(mapa: DTLMapa, pasos: Dictionary) -> Vector2i:
	var lejana := Vector2i(-1, -1)
	var maxima := -1
	for celda: Vector2i in pasos:
		var d: int = pasos[celda]
		if d > maxima:
			maxima = d
			lejana = celda
		elif d == maxima and _al_borde(celda, mapa.dimensiones()) < _al_borde(
				lejana, mapa.dimensiones()):
			lejana = celda
	return lejana


## Callejón sin salida lo más lejos posible de la puerta. Un callejón es una celda
## con un solo vecino transitable: si tiene más, es un cruce, y en un cruce se te
## puede saltar el enemigo desde cualquier lado.
##
## Antes se exigía que el callejón fuese el más lejano de la puerta, y eso metía
## la llave a diez pasos de la jugadora: como la puerta es justo la celda más
## lejana de ella, cualquier rama que arranque a su lado y acabe lejos de la
## salida cumple. Así que primero se descartan los callejones que regalan la llave
## por estar al lado, y entre los que quedan gana el más lejano de la salida.
##
## Si el laberinto no tiene ni un callejón, se cae a la celda transitable más
## lejana de la puerta, porque no colocar la llave ninguna deja la partida sin
## salida y eso no es una decisión de diseño: es un fallo.
func _celda_callejon_opuesto(mapa: DTLMapa, pasos_desde_salida: Dictionary,
		pasos_desde_jugadora: Dictionary, celda_salida: Vector2i) -> Vector2i:
	var mejor := Vector2i(-1, -1)
	var maxima := -1
	var mejor_inalcanzable := Vector2i(-1, -1)
	var maxima_inalcanzable := -1
	for celda: Vector2i in pasos_desde_salida:
		if celda == celda_salida or not _es_callejon(mapa, celda):
			continue
		var d: int = pasos_desde_salida[celda]
		if d > maxima_inalcanzable:
			maxima_inalcanzable = d
			mejor_inalcanzable = celda
		if pasos_desde_jugadora.get(celda, 0) < distancia_minima_llave:
			continue
		if d > maxima:
			maxima = d
			mejor = celda
	if mejor.x >= 0:
		return mejor
	if mejor_inalcanzable.x >= 0:
		push_warning("Objetivo: ningún callejón está a %d pasos de la jugadora; "
				% distancia_minima_llave
				+ "la llave va en el callejón más lejano de la salida.")
		return mejor_inalcanzable

	for celda: Vector2i in pasos_desde_salida:
		if celda == celda_salida:
			continue
		var d: int = pasos_desde_salida[celda]
		if d > maxima_inalcanzable:
			maxima_inalcanzable = d
			mejor_inalcanzable = celda
	push_warning("Objetivo: el laberinto no tiene callejones sin salida; "
			+ "la llave va en la celda transitable más lejana.")
	return mejor_inalcanzable


func _es_callejon(mapa: DTLMapa, celda: Vector2i) -> bool:
	var salidas := 0
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if mapa.es_transitable(celda + off):
			salidas += 1
	return salidas == 1


## Cuántos pasos hay de una celda a otra por el suelo transitable. Lo que no se
## llega no aparece en el diccionario, así que `get()` da -1 y eso ya dice que no
## hay camino.
func _pasos_desde(mapa: DTLMapa, inicio: Vector2i) -> Dictionary:
	var pasos: Dictionary = {}
	if not mapa.es_transitable(inicio):
		return pasos
	pasos[inicio] = 0
	var cola: Array[Vector2i] = [inicio]
	while not cola.is_empty():
		var actual: Vector2i = cola.pop_front()
		var base: int = pasos[actual]
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var vecina := actual + off
			if pasos.has(vecina) or not mapa.es_transitable(vecina):
				continue
			pasos[vecina] = base + 1
			cola.append(vecina)
	return pasos


## Distancia de una celda al borde del mapa. Cuanto menos, más pegada al borde.
func _al_borde(celda: Vector2i, d: Vector2i) -> int:
	return mini(mini(celda.x, celda.y), mini(d.x - 1 - celda.x, d.y - 1 - celda.y))
