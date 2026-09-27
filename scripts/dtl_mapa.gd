class_name DTLMapa
extends Node2D

# Mapa generado con la GDExtension `dtl` (addons/dtl).
# Las NavigationRegion2D se construyen AUTOMATICAMENTE a partir de la misma
# rejilla que se pinta, así que nunca se desincronizan del mapa.
#
# Uso:
#   $DTLMapa.generar()            -> una semilla nueva
#   $DTLMapa.generar(false)       -> reutiliza la semilla actual
#   $DTLMapa.punto_inicial()      -> celda transitable más amplia
#
# Detalle importante de Godot 2D: los polígonos de navegación sólo se conectan
# si se tocan EXACTAMENTE (ni un hueco ni un solape). Por eso las NavigationRegion
# se construyen con un particionado exacto de rectángulos (greedy merge).

enum Generador {
	ROGUELIKE, ## salas + pasillos
	ROGUELIKE_SIMPLE, ## salas + pasillos (algoritmo más simple)
	MAZE_DIG, ## laberinto clásico
	MAZE_BAR, ## laberinto de barras
	CLUSTERING_MAZE, ## laberinto con muros agrupados
	CELLULAR, ##|autómata celular (isla)
	CELLULAR_MIX, ## autómata celular mixto
	VORONOI, ## islas de Voronoi
	PERLIN, ## relieve de Perlin
	PERLIN_LOOP, ## Perlin en bucle
	PERLIN_SOLITARIO, ## Perlin con islas aisladas
	FRACTAL, ## relieve fractal
	FRACTAL_LOOP, ## fractal en bucle
	DIAMOND_SQUARE, ## diamond-square
	DIAMOND_SQUARE_CORNER, ## diamond-square con esquinas
}

enum Tipo { VACIO, MURO, SUELO, UMBRAL }

## Se emite al terminar cada `generar()`, para que lo que dependa de las
## dimensiones del mapa (como las señales por celda de SenalesTiles) se remonte
## sin tener que adivinar cuándo ha cambiado la rejilla.
signal generar_terminada(dimensiones: Vector2i)

## TileSet con el que se pinta. Si es null se construye uno proceduralmente.
@export var tile_set: TileSet

@export_group("Generación")
@export var generador: Generador = Generador.ROGUELIKE
@export_range(9, 401, 2) var ancho: int = 61
@export_range(9, 401, 2) var alto: int = 61
@export var semilla_aleatoria: bool = true
@export var semilla: int = 12345
## Rodea el mapa con un muro sólido para que no se pueda salir.
@export var marco: bool = true
@export var grosor_marco: int = 1
## Engrosa el suelo las celdas que se le pidan hacia cada lado. Los pasillos
## del RogueLike salen de un tile de ancho, así que con 1 el suelo se traga los
## muros de una celda y el mapa se convierte en una cueva: úsalo solo si el mapa
## es para otro tipo de cuerpo. Al ensanchar SÓLO el suelo nunca se pierde
## conectividad: cualquier ruta que había antes sigue existiendo.
@export_range(0, 6) var engrosar: int = 0

## Cuántos segundos marca cada bloque de muro el "chocado" de la onda de la Girl
## antes de volver a false. Está aquí y no sólo en Bloque porque los bloques se
## crean desde código, no desde una escena: si el plazo sólo estuviera en el
## script, cambiarlo obligaría a tocar código.
@export_range(0.1, 10.0, 0.1) var duracion_chocado_muro: float = 1.5

## Fracción de los bloques de muro que se generan como "sensibles". Son
## idénticos al resto mientras no llega nada (mismo color, mismo borde, misma
## física), pero la onda de la Girl los enciende en rojo en vez de en azul: la
## única pista para encontrarlos es lanzar ondas y ver cuáles responden
## distinto. La elección es determinista con `semilla`, así que con la misma
## semilla salen siempre los mismos.
@export_range(0.0, 1.0, 0.05) var proporcion_sensibles: float = 0.3

## Color con el que se enciende un bloque sensible al recibir la onda.
@export var color_sensible := Color(1.0, 0.3, 0.24)

## Anchura máxima de los pasillos, en tiles, contando con el pasillo. 1 deja el
## mapa tal cual sale de DTL, que es de pasillos de 1 tile. Con 2 se ensancha una
## parte de los pasillos para que el enemigo de 1.1 tiles quepa, y el resto se
## queda en 1 tile a propósito: así no todas las salas quedan conectadas entre sí
## y el enemigo de 1.1 tiles no puede ir a todas partes.
@export_range(1, 3) var pasillo_max: int = 2

## Fracción de pasillos estrechos que se ensanchan. 1 ensancha todos y deja el
## mismo ancho en todo el mapa; 0.5 deja una mezcla de pasillos anchos y estrechos.
@export_range(0.0, 1.0, 0.05) var proporcion_pasillo_ancho: float = 0.5

@export_group("Pintado y física")
@export_range(8, 128, 8) var tile: int = 32
@export var pintar: bool = true
@export var colision_muros: bool = true
## Capa propia de los muros, el bit 3 (valor 8). Vive separada de la de los
## personajes a propósito: el recorte de la onda lanza rayos con esta máscara, y
## si los muros compartieran capa con la Girl y el enemigo cada rayo saldría
## impactado por el cuerpo que tiene delante, que es justo lo que hay que evitar.
## Con la separación, `mascara_colision` (lo que los muros detectan) se queda en
## la capa de los personajes y no hay que tocar nada más para que todo encaje.
@export_flags_2d_physics var capa_colision: int = Bloque.CAPA_MURO
## Lo que detectan los muros. La capa 1 es la de los personajes.
@export_flags_2d_physics var mascara_colision: int = Bloque.CAPA_PERSONAJE

@export_group("Navegación")
@export var generar_navegacion: bool = true
@export var nombre_region: StringName = &"Navegacion"
## Lado del cuadrado de navegación, en tiles. Cada polígono es un cuadrado de
## `celda_navegacion` tiles, así que 2 reduce los polígonos a la cuarta parte y
## evita el truncamiento de rutas de Godot 4.7 en mapas enormes. Ojo: con 2 o
## más se cortan los pasillos de un solo tile de ancho.
@export_range(1, 8) var celda_navegacion: int = 1
## Lado del cuerpo que tiene que andar por la malla, en tiles. La malla se
## ERODE por este valor antes de construirla, de forma que los pasillos más
## estrechos que el cuerpo quedan directamente fuera de la navegación: es lo
## único que garantiza que la ruta no le mande a empotrarse donde no cabe. Con
## 1.1 el enemigo no usa los pasillos de un tile, pero sí los de dos, y con 0 se
## construye la malla sobre el suelo tal cual, sin erosionar.
@export_range(0.0, 4.0, 0.1) var cuerpo_nav: float = 1.1
## La erosión se calcula sobre una rejilla `resolucion_nav` veces más fina que
## los tiles. Hace falta porque un cuerpo de 1.1 tiles no cabe centrado en una
## celda suelta: en un pasillo de DOS tiles sólo entra centrado en la línea
## media, que cae justo en la frontera entre las dos celdas. Con la rejilla
## partida a la mitad aparecen puntos de paso a ambos lados de esa frontera.
@export_range(1, 4) var resolucion_nav: int = 2
## Log del resumen de la navegación al terminar de generar.
@export var depurar: bool = true

@export_group("Parámetros: RogueLike")
@export_range(1, 400) var max_ways: int = 90
@export var room_min: Vector2i = Vector2i(4, 4)
@export var room_max: Vector2i = Vector2i(10, 8)
@export var way_min: int = 1
@export var way_max: int = 5
@export var division_min: int = 4
@export var division_max: int = 8

@export_group("Parámetros: autómata / Voronoi")
@export_range(1, 12) var iteraciones: int = 5
@export_range(0.0, 1.0, 0.01) var probabilidad: float = 0.45
@export_range(1, 40) var land_values: int = 4
@export_range(1.0, 80.0, 1.0) var voronoi_num: float = 18.0

@export_group("Parámetros: relieve")
@export_range(0.005, 1.0, 0.005) var frecuencia: float = 0.1
@export_range(1, 8) var octavas: int = 4
@export var altura_min: int = 0
@export var altura_max: int = 40
@export var valor_min: int = 0
@export var valor_altura: int = 50
@export var valor_add: int = 20
## Porcentaje (0-1) de la altura mínima a partir del cual el terreno es transitable.
@export_range(0.0, 1.0, 0.01) var umbral: float = 0.4
## En los generadores binarios (0/1) invierte qué valor se considera muro.
@export var invertir: bool = false

var _rejilla: Array[Array] = []
var _datos: Array = []
var _dtl: Object = null
var _tiles_generados: TileMapLayer = null
var _bloques: Array[Bloque] = []
var _regiones: Array[NavigationRegion2D] = []
## Un byte por celda de la rejilla de navegación (más fina que los tiles cuando
## hay `cuerpo_nav`), 1 si el cuerpo cabe ahí. Se guarda para poder preguntar por
## la malla sin consultar al servidor, que tarda un frame en sincronizarse.
var _nav: PackedByteArray = PackedByteArray()
var _nav_cols: int = 0
var _nav_filas: int = 0


# Se genera en _enter_tree y no en _ready para que la NavigationRegion2D exista
# antes de que ningún otro nodo del juego (_ready va de hijos a padres, y aquí el
# mapa es el primero) consulte el mapa de navegación. La sincronización del
# servidor sigue necesitando un frame, pero así nadie llega antes que la malla.
func _enter_tree() -> void:
	generar(semilla_aleatoria)


# ---------------------------------------------------------------- API pública

## Genera el mapa. `nueva_semilla` solo importa si `semilla_aleatoria` está activo.
func generar(nueva_semilla: bool = true) -> void:
	if nueva_semilla and semilla_aleatoria:
		semilla = randi()
	_limpiar()

	_datos = _llamar_dtl()
	if _datos.is_empty():
		push_error("DTLMapa: %s devolvió una rejilla vacía." % Generador.keys()[generador])
		return

	_rejilla = _normalizar(_datos)
	if engrosar > 0:
		_engrosar_suelo(engrosar)
	_ensanchar_pasillos(pasillo_max)
	_recortar()
	if marco:
		_poner_marco(grosor_marco)

	if pintar:
		_construir_tilemap()
	if colision_muros:
		_construir_colision()
	if generar_navegacion:
		_construir_malla()

	if depurar:
		_imprimir_resumen()

	generar_terminada.emit(dimensiones())


func punto_inicial() -> Vector2:
	## Centro de la zona transitable más grande. Vector2.ZERO si el mapa no caminable.
	var rects := _particionar(Tipo.SUELO)
	var mejor := Rect2i()
	var area := -1
	for r in rects:
		var a := r.size.x * r.size.y
		if a > area:
			area = a
			mejor = r
	if area < 0:
		return Vector2.ZERO
	return _centro_celda(mejor.position + mejor.size / 2)


func es_transitable(celda: Vector2i) -> bool:
	if celda.y < 0 or celda.y >= _rejilla.size():
		return false
	var fila: Array = _rejilla[celda.y]
	if celda.x < 0 or celda.x >= fila.size():
		return false
	return _es_suelo(fila[celda.x])


## ¿Este tipo de celda se puede recorrer?
func _es_suelo(tipo: int) -> bool:
	return tipo == Tipo.SUELO or tipo == Tipo.UMBRAL


## Un bloque de `paso x paso` celdas sólo es navegable si TODAS son transitable,
## para no inventarse suelo donde hay muro.
func _bloque_libre(bx: int, by: int, paso: int) -> bool:
	for y in range(by, mini(by + paso, _rejilla.size())):
		var fila: Array = _rejilla[y]
		for x in range(bx, mini(bx + paso, fila.size())):
			if not _es_suelo(fila[x]):
				return false
	return true


func dimensiones() -> Vector2i:
	if _rejilla.is_empty():
		return Vector2i.ZERO
	var fila: Array = _rejilla[0]
	return Vector2i(fila.size(), _rejilla.size())


## Centro en píxeles de una celda, ya en coordenadas de mundo.
func centro_celda(celda: Vector2i) -> Vector2:
	return to_global(_centro_celda(celda))


## Todos los bloques de muro del mapa, uno por rectángulo. Vacío si
## `colision_muros` está apagado, porque entonces no se construye ninguno.
func bloques() -> Array[Bloque]:
	return _bloques


## Sólo los marcados como sensibles en esta generación: iguales que el resto en
## reposo, pero los que la onda de la Girl enciende en rojo.
func bloques_sensibles() -> Array[Bloque]:
	var salida: Array[Bloque] = []
	for bloque in _bloques:
		if bloque.sensible:
			salida.append(bloque)
	return salida


## El bloque de muro que cubre un punto del mundo, o null si ahí no hay muro.
## Lo usa la onda para marcar el trozo de muro que ha tocado, y las pruebas para
## comprobar que la marca salta de un bloque a su vecino y no al de más allá.
func bloque_en(punto: Vector2) -> Bloque:
	var local := to_local(punto)
	for bloque in _bloques:
		var col := bloque.get_child(0) as CollisionShape2D
		var forma := col.shape as RectangleShape2D
		var medio := forma.size * 0.5
		if absf(local.x - col.position.x) <= medio.x \
				and absf(local.y - col.position.y) <= medio.y:
			return bloque
	return null


## ¿Hay muro en esta celda? `es_transitable` incluye también el umbral, que sí es
## de suelo, así que para "esto es pared" hace falta esta.
func es_muro(celda: Vector2i) -> bool:
	if celda.y < 0 or celda.y >= _rejilla.size():
		return true
	var fila: Array = _rejilla[celda.y]
	if celda.x < 0 or celda.x >= fila.size():
		return true
	return fila[celda.x] == Tipo.MURO


## ¿Un punto del mundo cae en la malla de navegación? Responde con la máscara que
## se calculó al generar, así que contesta al instante y sin esperar a que el
## servidor sincronice. False en cualquier punto que no sea suelo navegable, lo
## que incluye los pasillos demasiado estrechos para `cuerpo_nav`.
func es_navegable(punto: Vector2) -> bool:
	if _nav.is_empty():
		# Sin máscara sólo hay malla si no se erosionó, y entonces vale el suelo.
		return es_transitable(celda_de(punto))
	var local := to_local(punto)
	var sub := float(tile) / float(maxi(resolucion_nav, 1))
	var cx := int(floor(local.x / sub))
	var cy := int(floor(local.y / sub))
	if cx < 0 or cy < 0 or cx >= _nav_cols or cy >= _nav_filas:
		return false
	return _nav[cy * _nav_cols + cx] != 0


## ¿La celda tiene algún punto navegable? Es más generoso que `es_navegable` en el
## centro, porque el centro de una celda no tiene por qué servir: en un pasillo de
## dos tiles el cuerpo sólo entra centrado en la frontera entre las dos celdas.
func celda_navegable(celda: Vector2i) -> bool:
	if not es_transitable(celda):
		return false
	if _nav.is_empty():
		return true
	var paso := maxi(resolucion_nav, 1)
	for dy in range(paso):
		for dx in range(paso):
			if es_navegable(_centro_sub(celda, dx, dy)):
				return true
	return false


## Centro de una de las subceldas en las que se divide una celda al navegar.
func _centro_sub(celda: Vector2i, dx: int, dy: int) -> Vector2:
	var sub := float(tile) / float(maxi(resolucion_nav, 1))
	var origen := _centro_celda(celda) - Vector2(tile, tile) * 0.5
	return to_global(origen + Vector2((dx + 0.5) * sub, (dy + 0.5) * sub))


## Celda que contiene un punto del mundo.
func celda_de(punto: Vector2) -> Vector2i:
	var local := to_local(punto)
	return Vector2i(int(floor(local.x / tile)), int(floor(local.y / tile)))


## ¿La celda está en una zona ABIERTA, o sea en una sala y no en un pasillo?
##
## No se puede mirar el tipo de celda para esto porque el RogueLike marca igual
## el suelo de la sala (2) y el del pasillo (4); lo único que los distingue es
## que el pasillo siempre tiene muro al lado. Así que se mira la holgura: con
## `holgura` >= 1 un pasillo de un tile queda descartado siempre, y una sala de
## tres tiles o más se acepta.
func es_sala(celda: Vector2i, holgura: int = 1) -> bool:
	for y in range(celda.y - holgura, celda.y + holgura + 1):
		for x in range(celda.x - holgura, celda.x + holgura + 1):
			if not es_transitable(Vector2i(x, y)):
				return false
	return true


## Celda de sala a una distancia de entre `minimo` y `radio` celdas de `desde`.
## Vector2i(-1, -1) si en ese radio no hay ninguna, para que quien llame pueda
## abrir el radio y no afuntar que no hay sitio.
func celda_sala_cerca(desde: Vector2i, radio: int, minimo: int = 1,
		holgura: int = 1) -> Vector2i:
	var candidatas: Array[Vector2i] = []
	for dy in range(-radio, radio + 1):
		for dx in range(-radio, radio + 1):
			# Distancia de Chebyshev: cuenta celdas de pasillo, no píxeles en
			# diagonal, que es lo que importa para un mapa de rejilla.
			var dist := maxi(absi(dx), absi(dy))
			if dist > radio or dist < minimo:
				continue
			var celda := desde + Vector2i(dx, dy)
			if es_sala(celda, holgura):
				candidatas.append(celda)
	if candidatas.is_empty():
		return Vector2i(-1, -1)
	return candidatas[randi() % candidatas.size()]


## Consulta real al servidor de navegación: comprueba que se puede ir de un
## punto transitable a otro. Devuelve true si encuentra ruta.
func probar_navegacion(desde: Vector2, hasta: Vector2) -> bool:
	var region := _primera_region()
	if region == null:
		return false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var mapa := region.get_navigation_map()
	var ruta := NavigationServer2D.map_get_path(mapa, desde, hasta, true)
	# Con solo mirar que haya 2 puntos no vale: por encima de ~3600 polígonos
	# Godot 4.7 devuelve una ruta TRUNCADA, y esa truncada también tiene puntos.
	# Lo que delata el fallo es que el último no llega al destino.
	var llega := not ruta.is_empty() and ruta[ruta.size() - 1].distance_to(hasta) < 2.0
	print("[DTLMapa] ruta ", desde, " -> ", hasta, ": ", ruta.size(), " puntos, ",
			"llega" if llega else "NO LLEGA (malla partidas o truncada)")
	return llega


# ---------------------------------------------------------------- DTL

func _llamar_dtl() -> Array:
	_dtl = DTL.new()
	_dtl.call("SetSeed", maxi(semilla, 0))
	var w := ancho
	var h := alto
	match generador:
		Generador.ROGUELIKE:
			return _datos_de(_dtl.call("RogueLike", w, h, max_ways,
					room_min.x, room_max.x, room_min.y, room_max.y,
					way_min, way_max, way_min, way_max))
		Generador.ROGUELIKE_SIMPLE:
			return _datos_de(_dtl.call("SimpleRogueLike", w, h, division_min, division_max,
					room_min.x, room_max.x, room_min.y, room_max.y))
		Generador.MAZE_DIG:
			return _datos_de(_dtl.call("MazeDig", w, h))
		Generador.MAZE_BAR:
			return _datos_de(_dtl.call("MazeBar", w, h))
		Generador.CLUSTERING_MAZE:
			return _datos_de(_dtl.call("ClusteringMaze", w, h))
		Generador.CELLULAR:
			return _datos_de(_dtl.call("CellularAutomatonIsland", w, h, iteraciones, probabilidad))
		Generador.CELLULAR_MIX:
			return _datos_de(_dtl.call("CellularAutomatonMixIsland", w, h, land_values, iteraciones))
		Generador.VORONOI:
			return _datos_de(_dtl.call("SimpleVoronoiIsland", w, h, voronoi_num, probabilidad))
		Generador.PERLIN:
			return _datos_de(_dtl.call("PerlinIsland", w, h, frecuencia, octavas, altura_max, altura_min))
		Generador.PERLIN_LOOP:
			return _datos_de(_dtl.call("PerlinLoopIsland", w, h, frecuencia, octavas, altura_max, altura_min))
		Generador.PERLIN_SOLITARIO:
			return _datos_de(_dtl.call("PerlinSolitaryIsland", w, h, 0.2, 0.3,
					frecuencia, octavas, altura_max, altura_min))
		Generador.FRACTAL:
			return _datos_de(_dtl.call("FractalIsland", w, h, valor_min, valor_altura, valor_add))
		Generador.FRACTAL_LOOP:
			return _datos_de(_dtl.call("FractalLoopIsland", w, h, valor_min, valor_altura, valor_add))
		Generador.DIAMOND_SQUARE:
			return _datos_de(_dtl.call("DiamondSquareAverageIsland", w, h, valor_min, valor_altura, valor_add))
		Generador.DIAMOND_SQUARE_CORNER:
			return _datos_de(_dtl.call("DiamondSquareAverageCornerIsland", w, h,
					valor_min, valor_altura, valor_add))
	return []


static func _datos_de(resultado: Variant) -> Array:
	return resultado as Array


# ---------------------------------------------------------------- normalización

## Convierte la salida heterogénea de DTL a una rejilla canónica de `Tipo`.
func _normalizar(datos: Array) -> Array[Array]:
	match generador:
		Generador.ROGUELIKE:
			# 0 = fuera, 1 = muro, 2 = suelo de sala, 3 = puerta, 4 = pasillo
			return _mapear(datos, {0: Tipo.VACIO, 1: Tipo.MURO, 2: Tipo.SUELO, 3: Tipo.UMBRAL, 4: Tipo.SUELO})
		Generador.ROGUELIKE_SIMPLE:
			# 0 = fuera, 1 = muro, 2 = suelo
			return _mapear(datos, {0: Tipo.VACIO, 1: Tipo.MURO, 2: Tipo.SUELO})
		Generador.PERLIN, Generador.PERLIN_LOOP, Generador.PERLIN_SOLITARIO, \
		Generador.FRACTAL, Generador.FRACTAL_LOOP, \
		Generador.DIAMOND_SQUARE, Generador.DIAMOND_SQUARE_CORNER:
			return _desde_altura(datos)
	return _desde_binario(datos)


static func _mapear(datos: Array, reglas: Dictionary) -> Array[Array]:
	var salida: Array[Array] = []
	for fila in datos:
		var nueva: Array = []
		nueva.resize(fila.size())
		for i in range(fila.size()):
			nueva[i] = reglas.get(fila[i], Tipo.VACIO)
		salida.append(nueva)
	return salida


## Los laberintos y autómatas devuelven 0/1 pero cada generador invierte el
## sentido. Se deduce mirando qué valor domina en el borde exterior, que en
## todos ellos es el muro.
func _desde_binario(datos: Array) -> Array[Array]:
	var h := datos.size()
	var w := (datos[0] as Array).size()
	var conteo := {}
	for x in range(w):
		conteo[datos[0][x]] = conteo.get(datos[0][x], 0) + 1
		conteo[datos[h - 1][x]] = conteo.get(datos[h - 1][x], 0) + 1
	for y in range(h):
		conteo[datos[y][0]] = conteo.get(datos[y][0], 0) + 1
		conteo[datos[y][w - 1]] = conteo.get(datos[y][w - 1], 0) + 1

	var muro: int = datos[0][0]
	var mejor := -1
	for valor in conteo:
		if conteo[valor] > mejor:
			mejor = conteo[valor]
			muro = valor
	if invertir:
		muro = 1 - muro

	var salida: Array[Array] = []
	for fila in datos:
		var nueva: Array = []
		nueva.resize(fila.size())
		for i in range(fila.size()):
			nueva[i] = Tipo.MURO if fila[i] == muro else Tipo.SUELO
		salida.append(nueva)
	return salida


## Los generadores de relieve devuelven alturas que no respetan su propio rango,
## así que se normalizan a 0-1 y se corta con `umbral`.
func _desde_altura(datos: Array) -> Array[Array]:
	var minimo := 99999999
	var maximo := -99999999
	for fila in datos:
		for v in fila:
			minimo = mini(minimo, v)
			maximo = maxi(maximo, v)
	var rango := float(maximo - minimo)
	var salida: Array[Array] = []
	for fila in datos:
		var nueva: Array = []
		nueva.resize(fila.size())
		for i in range(fila.size()):
			var t := 0.0 if rango <= 0.0 else (float(fila[i]) - float(minimo)) / rango
			nueva[i] = Tipo.SUELO if t >= umbral else Tipo.MURO
		salida.append(nueva)
	return salida


## Recorta el margen vacío que dejan los generadores de salas.
func _recortar() -> void:
	var minx := 99999999
	var miny := 99999999
	var maxx := -1
	var maxy := -1
	for y in range(_rejilla.size()):
		var fila: Array = _rejilla[y]
		for x in range(fila.size()):
			if fila[x] != Tipo.VACIO:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return
	var recortada: Array[Array] = []
	for y in range(miny, maxy + 1):
		var fila: Array = _rejilla[y]
		recortada.append(fila.slice(minx, maxx + 1))
	_rejilla = recortada


func _poner_marco(grosor: int) -> void:
	var h := _rejilla.size()
	if h == 0:
		return
	var w := (_rejilla[0] as Array).size()
	for y in range(h):
		var fila: Array = _rejilla[y]
		for x in range(w):
			if y < grosor or x < grosor or y >= h - grosor or x >= w - grosor:
				fila[x] = Tipo.MURO


## Convierte en suelo todo muro que esté a `radio` celdas o menos de otra celda
## de suelo, y deja el resto como estaba. Se calcula sobre una copia: si se
## modificara en el sitio, el suelo recién creado ampliaría el engrosado sin
## control en las esquinas.
func _engrosar_suelo(radio: int) -> void:
	var copia: Array = []
	for fila: Array in _rejilla:
		copia.append(fila.duplicate())
	var h := _rejilla.size()
	var w := (_rejilla[0] as Array).size()
	for y in range(h):
		for x in range(w):
			if _es_suelo(copia[y][x]):
				continue
			var cerca := false
			for dy in range(-radio, radio + 1):
				for dx in range(-radio, radio + 1):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if _es_suelo(copia[ny][nx]):
						cerca = true
						break
				if cerca:
					break
			if cerca:
				_rejilla[y][x] = Tipo.SUELO


## Convierte muros en suelo ensanchando a `pasillo_max` tiles los pasillos
## estrechos, y deja el resto como estaban. DTL sólo garantiza pasillos de UN
## tile: su `way_min`/`way_max` no controlan la anchura (medido: con `way_max` de 1
## a 8 la mezcla de anchos apenas cambia, y los tramos de 2 tiles que salen son
## parches sueltos en las junctions, no pasillos). Como el ancho decide si el
## enemigo cabe o no, hace falta que el ancho sea algo que se pueda controlar.
##
## Se agrupan las celdas de pasillo de 1 tile por\Test connectivity, y cada grupo
## se ensancha por UN lado, el mismo para todo el grupo: si se alternase lado a
## celda saldrían dientes de sierra en vez de un pasillo. Un grupo al que no se le
## puede ensanchar (le rodea el borde del mapa) se deja en 1 tile, que también es
## justo lo que se quiere: no todos los pasillos pueden ser anchos.
func _ensanchar_pasillos(ancho_max: int) -> void:
	if ancho_max <= 1 or _rejilla.is_empty():
		return
	for _vuelta in range(4):
		var grupos := _grupos_de_pasillo()
		if grupos.is_empty():
			return
		var tocados := 0
		for grupo in grupos:
			if _anchura_de(grupo[0]) >= ancho_max:
				continue
			if randf() > proporcion_pasillo_ancho:
				continue
			if not _ensanchar_grupo(grupo):
				continue
			tocados += 1
		if tocados == 0:
			return


## Ancho local de una celda: cuántas celdas de suelo hay en línea recta a cada
## lado, y el menor de los dos ejes. En un pasillo de 1 tile da 1; en una sala
## de 3x3 o más da 3 o más.
func _anchura_de(celda: Vector2i) -> int:
	return mini(_recorrido(celda, Vector2i(1, 0)), _recorrido(celda, Vector2i(0, 1)))


func _recorrido(celda: Vector2i, dir: Vector2i) -> int:
	var total := 0
	for signo: int in [1, -1]:
		var paso: Vector2i = dir * signo
		var c := celda + paso
		while es_transitable(c) and _es_suelo_pasillo(c):
			total += 1
			c += paso
	return total + 1


## Las celdas estrechas de un pasillo no son sólo las de suelo: un pasillo de 1
## tile entre salas lleva suelo, y a los lados pared. Se agrupan las celdas de
## SUELO cuyo ancho local es 1 y que conectan con otra igual.
func _grupos_de_pasillo() -> Array:
	var h := _rejilla.size()
	var w := (_rejilla[0] as Array).size()
	var visto := {}
	var grupos: Array = []
	for y in h:
		for x in w:
			var inicio := Vector2i(x, y)
			if visto.has(inicio) or not es_transitable(inicio):
				continue
			if _anchura_de(inicio) > 1:
				continue
			var grupo := _inundar(inicio, visto, true)
			grupos.append(grupo)
	return grupos


## Inundación en 4 direcciones. `solo_estrechas` limita el grupo a celdas del
## mismo tipo de pasillo, que es lo que hace falta para no comerse media sala.
func _inundar(inicio: Vector2i, visto: Dictionary, solo_estrechas: bool) -> Array:
	var grupo: Array = [inicio]
	visto[inicio] = true
	var cola: Array = [inicio]
	while not cola.is_empty():
		var actual: Vector2i = cola.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var v := actual + d
			if visto.has(v) or not es_transitable(v):
				continue
			if solo_estrechas and _anchura_de(v) > 1:
				continue
			visto[v] = true
			grupo.append(v)
			cola.append(v)
	return grupo


## Pasa a suelo las celdas de muro que hay al lado del grupo, todas por el mismo
## lado. Devuelve false si no hay sitio, que pasa en los pasillos que se apoyan
## en el borde del mapa.
func _ensanchar_grupo(grupo: Array) -> bool:
	var eje := _eje_del_grupo(grupo)
	if eje == Vector2i.ZERO:
		return false
	var lateral := Vector2i(-eje.y, eje.x)

	var mejor_lado := Vector2i.ZERO
	var mejor_cuenta := 0
	for signo: int in [1, -1]:
		var lado: Vector2i = lateral * signo
		var cuenta := 0
		for celda: Vector2i in grupo:
			var v: Vector2i = celda + lado
			if _es_muro(v):
				cuenta += 1
		if cuenta > mejor_cuenta:
			mejor_cuenta = cuenta
			mejor_lado = lado
	if mejor_cuenta == 0:
		return false

	for celda: Vector2i in grupo:
		var v: Vector2i = celda + mejor_lado
		if _es_muro(v):
			_rejilla[v.y][v.x] = Tipo.SUELO
	return true


## Eje mayor de un grupo de celdas: si se extiende más en horizontal que en
## vertical, es un pasillo horizontal y se ensancha en vertical, y al revés.
func _eje_del_grupo(grupo: Array) -> Vector2i:
	var minx := 99999999
	var maxx := -1
	var miny := 99999999
	var maxy := -1
	for celda: Vector2i in grupo:
		minx = mini(minx, celda.x)
		maxx = maxi(maxx, celda.x)
		miny = mini(miny, celda.y)
		maxy = maxi(maxy, celda.y)
	if maxx - minx >= maxy - miny:
		return Vector2i(1, 0)
	return Vector2i(0, 1)


func _es_muro(celda: Vector2i) -> bool:
	if celda.y < 0 or celda.y >= _rejilla.size():
		return false
	var fila: Array = _rejilla[celda.y]
	if celda.x < 0 or celda.x >= fila.size():
		return false
	return fila[celda.x] == Tipo.MURO


func _es_suelo_pasillo(celda: Vector2i) -> bool:
	return es_transitable(celda)


# ---------------------------------------------------------------- particionado
## Particiona las celdas de un tipo en rectángulos que se tocan exactamente y
## nunca se solapan. Ese requisito es el que hace que la navegación funcione.
func _particionar(tipo: int) -> Array[Rect2i]:
	var salida: Array[Rect2i] = []
	if _rejilla.is_empty():
		return salida
	var h := _rejilla.size()
	var w := (_rejilla[0] as Array).size()
	var usado: Array = []
	for y in range(h):
		var fila: Array = []
		fila.resize(w)
		fila.fill(false)
		usado.append(fila)

	for y in range(h):
		for x in range(w):
			if usado[y][x] or _rejilla[y][x] != tipo:
				continue
			var rw := 1
			while x + rw < w and not usado[y][x + rw] and _rejilla[y][x + rw] == tipo:
				rw += 1
			var rh := 1
			while y + rh < h:
				var cabe := true
				for i in range(rw):
					if usado[y + rh][x + i] or _rejilla[y + rh][x + i] != tipo:
						cabe = false
						break
				if not cabe:
					break
				rh += 1
			for j in range(rh):
				for i in range(rw):
					usado[y + j][x + i] = true
			salida.append(Rect2i(x, y, rw, rh))
	return salida


# ---------------------------------------------------------------- construcción

func _limpiar() -> void:
	for hijo in get_children():
		remove_child(hijo)
		hijo.queue_free()
	_tiles_generados = null
	_bloques.clear()
	_regiones.clear()
	_rejilla.clear()


func _construir_tilemap() -> void:
	var capa := TileMapLayer.new()
	capa.name = "Suelo"
	capa.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capa.tile_set = tile_set if tile_set != null else DTLTileSet.crear(tile, semilla)
	for y in range(_rejilla.size()):
		var fila: Array = _rejilla[y]
		for x in range(fila.size()):
			var tipo: int = fila[x]
			if tipo == Tipo.VACIO:
				continue
			var variante := absi(hash(Vector2i(x * 73856093, y * 19349663)) ^ semilla)
			capa.set_cell(Vector2i(x, y), 0, DTLTileSet.indice_para(_fila_atlas(tipo), variante))
	add_child(capa)
	_tiles_generados = capa


func _construir_colision() -> void:
	# Un cuerpo por rectángulo de muro, y no UN cuerpo con todos los rectángulos
	# dentro. La diferencia se nota justo en esto: la onda de la Girl choca contra
	# un cuerpo concreto y hay que poder poner la marca de "chocado" en ese trozo
	# de muro y no en el mapa entero. Con un solo cuerpo, un chocado en la
	# esquina norte encendería el "chocado" de los muros del sur.
	var contenedor := Node2D.new()
	contenedor.name = "Muros"
	for r in _particionar(Tipo.MURO):
		var bloque := Bloque.new()
		bloque.duracion_chocado = duracion_chocado_muro
		bloque.sensible = _es_sensible(r)
		if bloque.sensible:
			bloque.color_chocado_sensible = color_sensible
		bloque.collision_layer = capa_colision
		bloque.collision_mask = mascara_colision
		var forma := RectangleShape2D.new()
		forma.size = Vector2(r.size.x * tile, r.size.y * tile)
		var col := CollisionShape2D.new()
		col.shape = forma
		col.position = Vector2(r.position.x * tile + r.size.x * tile * 0.5,
				r.position.y * tile + r.size.y * tile * 0.5)
		bloque.add_child(col)
		contenedor.add_child(bloque)
		_bloques.append(bloque)
	add_child(contenedor)


## ¿Este rectángulo de muro sale sensible? Sólo cambia el color con el que se
## enciende al chocar la onda de la Girl: para el resto (dibujo en reposo,
## física, recorte del cono) es un bloque más.
##
## El hash mezcla posición, tamaño y `semilla` con la misma fórmula con la que
## `_construir_tilemap` elige la variante de tesela, así que el reparto sale
## distinto en cada rectángulo, se baraja entero al cambiar de semilla y, con
## la misma semilla, siempre salen los mismos.
func _es_sensible(r: Rect2i) -> bool:
	if proporcion_sensibles <= 0.0:
		return false
	var variante := absi(hash(Vector2i(
			r.position.x * 73856093 + r.size.x * 19349663,
			r.position.y * 19349663 + r.size.y * 73856093)) ^ semilla)
	return variante % 10000 < int(roundi(proporcion_sensibles * 10000.0))


## Construye la malla, erosionada por el cuerpo si hace falta. Si la erosión se
## queda sin nada (un mapa de pasillos de un solo tile no tiene ni un punto por
## el que quepa un cuerpo de 1.1 tiles) se vuelve a construir sin ella, porque
## peor un enemigo que roza los muros que un enemigo que no se mueve.
func _construir_malla() -> void:
	_nav = PackedByteArray()
	_nav_cols = 0
	_nav_filas = 0
	if cuerpo_nav > 0.0:
		_construir_navegacion_erosionada()
		if not _regiones.is_empty():
			return
		push_warning("DTLMapa: con `cuerpo_nav` de %.2f tiles no queda malla navegable; "
				% cuerpo_nav
				+ "se construye sin erosionar. Baja `cuerpo_nav`, o usa un mapa de salas "
				+ "con pasillos de dos tiles, que es lo que sí aguanta ese cuerpo.")
	_construir_navegacion()


## Un polígono POR CELDA transitable, no rectángulos fusionados.
##
## Godot 2D sólo enlaza dos polígonos de navegación si comparten una arista
## COMPLETA por ambos lados. Un reparto de rectángulos fusionados (que es lo
## que optimiza la colisión) genera uniones en T: un rectángulo largo pegado a
## varios cortos, y esas uniones no se conectan nunca. Un cuadrado por celda
## obliga a que cada arista sea completa, así que la navegación siempre funciona.
##
## `celda_navegacion` agrupa celdas para reducir el número de polígonos en mapas
## grandes, porque por encima de ~3600 polígonos `NavigationServer2D.map_get_path`
## de Godot 4.7 entrega rutas truncadas (las conexiones están bien; el recorte es
## del servidor). Con celda_navegacion = 1 y 61x61 celdas vamos sobrados.
func _construir_navegacion() -> void:
	var lado := float(tile * maxi(celda_navegacion, 1))
	var paso := maxi(celda_navegacion, 1)
	var alto := _rejilla.size()
	var ancho := (_rejilla[0] as Array).size() if not _rejilla.is_empty() else 0

	var poly := NavigationPolygon.new()
	var verts := PackedVector2Array()
	var indices: Array = []
	for by in range(0, alto, paso):
		for bx in range(0, ancho, paso):
			if not _bloque_libre(bx, by, paso):
				continue
			var origen := Vector2(bx * lado, by * lado)
			var b := verts.size()
			verts.append(origen)
			verts.append(origen + Vector2(lado, 0.0))
			verts.append(origen + Vector2(lado, lado))
			verts.append(origen + Vector2(0.0, lado))
			indices.append(PackedInt32Array([b, b + 1, b + 2, b + 3]))

	_fregar_navegacion(poly, verts, indices)


## Malla erosionada por el cuerpo. Se recorre una rejilla `resolucion_nav` veces
## más fina que el tile y sólo se emite un polígono donde el cuerpo cabe entero.
## Los subcuadrados contiguos comparten arista exacta, que es lo que Godot
## necesita para enlazarlos.
func _construir_navegacion_erosionada() -> void:
	var sub := float(tile) / float(maxi(resolucion_nav, 1))
	var medio := cuerpo_nav * float(tile) * 0.5
	var cols := _rejilla[0] as Array
	var filas := _rejilla.size()
	var n_sub := resolucion_nav

	_nav_cols = cols.size() * n_sub
	_nav_filas = filas * n_sub
	_nav.resize(_nav_cols * _nav_filas)
	_nav.fill(0)

	var poly := NavigationPolygon.new()
	var verts := PackedVector2Array()
	var indices: Array = []
	for cy in range(_nav_filas):
		for cx in range(_nav_cols):
			var centro := Vector2((cx + 0.5) * sub, (cy + 0.5) * sub)
			if not _cabe_cuerpo(centro, medio):
				continue
			_nav[cy * _nav_cols + cx] = 1
			var origen := Vector2(cx * sub, cy * sub)
			var b := verts.size()
			verts.append(origen)
			verts.append(origen + Vector2(sub, 0.0))
			verts.append(origen + Vector2(sub, sub))
			verts.append(origen + Vector2(0.0, sub))
			indices.append(PackedInt32Array([b, b + 1, b + 2, b + 3]))
	if indices.is_empty():
		_nav = PackedByteArray()
		_nav_cols = 0
		_nav_filas = 0
	_fregar_navegacion(poly, verts, indices)


## ¿El cuadrado de lado `2*medio` centrado en `centro` cabe entero en el suelo?
## Se miran todas las celdas que el cuadrado pisa, incluidas las de las esquinas.
func _cabe_cuerpo(centro: Vector2, medio: float) -> bool:
	var x0 := int(floor((centro.x - medio) / tile))
	var x1 := int(floor((centro.x + medio - 0.001) / tile))
	var y0 := int(floor((centro.y - medio) / tile))
	var y1 := int(floor((centro.y + medio - 0.001) / tile))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not es_transitable(Vector2i(x, y)):
				return false
	return true


func _fregar_navegacion(poly: NavigationPolygon, verts: PackedVector2Array,
		indices: Array) -> void:
	if indices.is_empty():
		# Ni con erosión ni sin ella queda malla: se deja al mapa sin navegar en
		# vez de crear una región vacía, que el servidor no se traga bien.
		_regiones.clear()
		return
	poly.vertices = verts
	for idx in indices:
		poly.add_polygon(idx)
	if indices.size() > 3600:
		push_warning("DTLMapa: %d polígonos de navegación. Por encima de ~3600, " % indices.size()
				+ "NavigationServer2D.map_get_path() de Godot 4.7 devuelve rutas truncadas. "
				+ "Baja `ancho`/`alto` o sube `cuerpo_nav`, que deja fuera los pasillos "
				+ "estrechos. Subir `resolucion_nav` empeoraría esto: multiplica los polígonos.")

	var region := NavigationRegion2D.new()
	region.name = nombre_region
	region.use_edge_connections = true
	region.navigation_polygon = poly
	add_child(region)
	_regiones.append(region)


func _primera_region() -> NavigationRegion2D:
	return _regiones[0] if not _regiones.is_empty() else null


# ---------------------------------------------------------------- utilidades

func _centro_celda(celda: Vector2i) -> Vector2:
	return Vector2(celda.x * tile + tile * 0.5, celda.y * tile + tile * 0.5)


## Fila del atlas que corresponde a un tipo de celda canónico.
func _fila_atlas(tipo: int) -> int:
	match tipo:
		Tipo.MURO:
			return DTLTileSet.MURO
		Tipo.UMBRAL:
			return DTLTileSet.UMBRAL
	return DTLTileSet.SUELO


func _imprimir_resumen() -> void:
	var d := dimensiones()
	var muros := _particionar(Tipo.MURO)
	var region := _primera_region()
	var poligonos := 0
	if region != null:
		poligonos = region.navigation_polygon.get_polygon_count()
	print("[DTLMapa] %s semilla=%d -> %dx%d celdas (%dx%d px)" % [
			Generador.keys()[generador], semilla, d.x, d.y, d.x * tile, d.y * tile])
	print("[DTLMapa] navegación: %d polígonos | colisión: %d rectángulos | suelo inicial: %s" % [
			poligonos, muros.size(), punto_inicial()])


func _on_zona_muerte_area_entered(area: Area2D) -> void:
	pass # Replace with function body.
