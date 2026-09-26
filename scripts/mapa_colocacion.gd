class_name MapaColocacion
extends Node

# Coloca nodos sobre celdas transitables del mapa generado por DTLMapa.
#
# Sin esto, la jugadora y el enemigo se quedan dentro de los muros, porque sus
# posiciones están puestas a mano para el pasillo antiguo. Además, de entre todas
# las celdas válidas se prefiere la más despejada, para que no aparezcan
# encajados en un pasillo.

@export var mapa: NodePath = NodePath("../MapaDTL")
@export var nodos: Array[NodePath] = []
## Celda por la que se empieza a buscar. (-1, -1) = centro del mapa.
@export var celda_preferida := Vector2i(-1, -1)
## Separa a los nodos entre sí para que no aparezcan apilados en la misma celda.
@export var separacion: float = 96.0
## Cuántas celdas libres alrededor se consideran sitio de sobra. Se busca con
## este margen y, si no hay ninguna celda que lo cumpla, se afloja.
@export var holgura: int = 2


func _ready() -> void:
	# Sin `await`: DTLMapa ya ha generado en su _enter_tree, así que la rejilla
	# existe y se puede colocar de inmediato. Importa que sea síncrono, porque
	# ColocarEnMapa va antes que girl y Enemigo en el orden de _ready, y así
	# ellos leen su posición final en el suyo.
	var destino := get_node_or_null(mapa) as DTLMapa
	if destino == null:
		push_warning("MapaColocacion: no encuentro el mapa en '%s'." % mapa)
		return

	# El RogueLike a veces deja salas sueltas, sin pasillo que las una con el
	# resto. Colocar a la jugadora en una y al enemigo en otra deja la partida
	# imposible: él no tiene por dónde ir. La colocación se acota a la
	# componente transitable más grande, así los dos siempre están juntos.
	var region := _componente_mayor(destino)
	var ocupadas: Array[Vector2] = []
	for ruta in nodos:
		var nodo := get_node_or_null(ruta) as Node2D
		if nodo == null:
			push_warning("MapaColocacion: no encuentro el nodo '%s'." % ruta)
			continue
		var celda := _sitio(destino, region, ocupadas)
		if celda.x < 0:
			# No queda ni una celda transitable: se avisa y se deja al nodo donde
			# estaba, porque moverlo a ciegas no lo arregla.
			push_warning("MapaColocacion: el mapa no tiene suelo para '%s'." % ruta)
			continue
		var centro := Vector2(celda.x * destino.tile + destino.tile * 0.5,
				celda.y * destino.tile + destino.tile * 0.5)
		nodo.global_position = destino.to_global(centro)
		ocupadas.append(nodo.global_position)


## Celda donde colocar el nodo: la transitable más cercana a la preferencia y con
## el mayor hueco alrededor. Se pide la holgura exportada, pero si el mapa es
## tan de pasillos que no la cumple en ninguna parte, se va bajando hasta 0: es
# mejor rozar un muro que aparecer dentro de él.
func _sitio(mapa: DTLMapa, region: Dictionary, ocupadas: Array[Vector2]) -> Vector2i:
	for margen in range(maxi(holgura, 0), -1, -1):
		var celda := _mejor_celda(mapa, region, margen, ocupadas)
		if celda.x >= 0:
			return celda
	return Vector2i(-1, -1)


## Celda transitable más cercana a la preferencia, sin pisar las ya ocupadas y
## con `margen` celdas libres alrededor.
func _mejor_celda(mapa: DTLMapa, region: Dictionary, margen: int,
		ocupadas: Array[Vector2]) -> Vector2i:
	var d := mapa.dimensiones()
	if d == Vector2i.ZERO:
		return Vector2i(-1, -1)
	var base := celda_preferida
	if base.x < 0 or base.y < 0:
		base = Vector2i(d.x / 2, d.y / 2)
	base.x = clampi(base.x, 0, d.x - 1)
	base.y = clampi(base.y, 0, d.y - 1)

	var mejor := Vector2i(-1, -1)
	var mejor_puntuacion := INF
	for y in range(d.y):
		for x in range(d.x):
			var celda_id := Vector2i(x, y)
			if not region.is_empty() and not region.has(celda_id):
				continue
			if not _libre_alrededor(mapa, celda_id, margen):
				continue
			var celda := Vector2(x * mapa.tile + mapa.tile * 0.5, y * mapa.tile + mapa.tile * 0.5)
			# Cuanto más lejos del punto pedido, peor. Y estar encima de otro
			# nodo se multiplica por 10, porque si no basta con acercarse un
			# poco a la preferencia y todos acaban amontonados en el mismo sitio.
			var puntuacion := Vector2(base - Vector2i(x, y)).length()
			for ocupada in ocupadas:
				puntuacion += maxf(separacion - (celda - ocupada).length(), 0.0) * 10.0
			if puntuacion < mejor_puntuacion:
				mejor_puntuacion = puntuacion
				mejor = Vector2i(x, y)
	return mejor


## La celda y las `margen` que la rodean tienen que ser transitables. Con margen 0
## sólo importa la celda en sí, que es lo único que el cuerpo no puede negociar.
func _libre_alrededor(mapa: DTLMapa, celda: Vector2i, margen: int) -> bool:
	for y in range(celda.y - margen, celda.y + margen + 1):
		for x in range(celda.x - margen, celda.x + margen + 1):
			if not mapa.es_transitable(Vector2i(x, y)):
				return false
	return true


## Conjunto de celdas de la componente transitable más grande. Vacío si el mapa
## no tiene nada transitable, y entonces da igual: la colocación se relaja sola.
func _componente_mayor(mapa: DTLMapa) -> Dictionary:
	var d := mapa.dimensiones()
	var visitadas := {}
	var mejor := {}
	for y in range(d.y):
		for x in range(d.x):
			var inicio := Vector2i(x, y)
			if visitadas.has(inicio) or not mapa.es_transitable(inicio):
				continue
			var grupo := _inundar(mapa, inicio, visitadas)
			if grupo.size() > mejor.size():
				mejor = grupo
	return mejor


## Recorrido en anchura de todas las celdas transitables que se tocan con la
## dada. Las marcadas en `visitadas` se saltan, así que sirve para ir
## recorriendo componentes enteras una a una.
func _inundar(mapa: DTLMapa, inicio: Vector2i, visitadas: Dictionary) -> Dictionary:
	var d := mapa.dimensiones()
	var grupo := {}
	var cola: Array[Vector2i] = [inicio]
	visitadas[inicio] = true
	while not cola.is_empty():
		var actual: Vector2i = cola.pop_back()
		grupo[actual] = true
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var vecina := actual + off
			if not visitadas.has(vecina) and mapa.es_transitable(vecina):
				visitadas[vecina] = true
				cola.append(vecina)
	return grupo
