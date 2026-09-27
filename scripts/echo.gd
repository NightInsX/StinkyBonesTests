class_name Echo
extends Node2D

# Onda cónica: un sector que se abre `angulo` grados y apunta en la
# dirección de rotation (la del ratón en el momento de lanzarla).
#
# La onda sólo lleva un Area2D con el cono entero, montado una sola vez. Cada
# objeto que quiera "oírla" se suscribe con su propio Area2D (ver
# scripts/pasillo.gd), así que no hace falta ninguna lista de cuerpos detectados
# aquí ni conectar señales a mano. Ese solape sólo sirve para enterarse de que la
# onda existe: el recorte contra los muros no lo toca, vive en `_distancias` y lo
# consultan `alcanza()`, el dibujo y los rayos.
#
# Lo que hace con los muros depende de quién la lanza. Las ondas de la Girl se
# recortan contra ellos: el cono no se dibuja entero, sino que cada dirección
# avanza hasta el primer muro, de forma que la onda suena y se ve por donde
# puede sonar de verdad, o sea los pasillos que están a la vista y no a través de
# las paredes. Las del enemigo atraviesan los muros, porque son las que tantrean
# a la jugadora: si se pararan en el primer muro no tantearían nada. Ver
# `recortada` en _ready().
const AREA_GROUP := "echo_onda"
## Grupo del nodo raiz de la onda. El Area2D de arriba es anónimo para la
## física (que sólo necesita la forma), pero quien quiera saber CUÁNDO termina
## la onda, de qué color es o hacia dónde apunta necesita el nodo entero, así
## que la raíz también se apunta a un grupo. Ver scripts/senales_tiles.gd.
const FUENTE_GROUP := "eco_fuente"

# Capas de colisión: deciden quién oye a quién. Quien lanza la onda elige en
# qué capa la mete, y cada oyente pone en su máscara las capas que le
# interesan. Así el filtrado lo hace la física y ningún script tiene que
# descartar ondas ajenas a mano.
const CAPA_ONDA_JUGADORA := 2  # bit 1: la oye el enemigo
const CAPA_ONDA_ENEMIGA := 4  # bit 2: solo la oye la Girl

## En qué capa pone `DTLMapa` los muros. Ahora es una capa propia y no la 1 de
## los personajes: los rayos del recorte la usan de máscara, y si los muros
## compartieran capa con la Girl cada rayo saldría impactado por el cuerpo que
## tiene delante.
const CAPA_MURO := Bloque.CAPA_MURO

@export var max_radius : float = 200.0 #Radio si se necesita se aumenta
@export var duration:float = 1 #duracion en pantalla
@export var ring_count = 2	#puramente cosmetico
@export var ring_delay = 0.1
@export var color_wave :Color = Color(1.0, 1.0, 1.0)
@export var line_width = 3
@export var angulo : float = 45.0  # apertura del cono, en grados
@export var capa : int = 1  # en qué collision_layer se mete la onda
## Capas de muro contra las que se recorta la onda. Vacío = no se recorta.
@export_flags_2d_physics var capas_muro: int = CAPA_MURO

## En cuántos tramos se parte el cono para recortarlo. Cada tramo mide una
## franja angular y guarda su radio, así que `alcanza()` y el dibujo resuelven el
## recorte con esa resolución. Son unos pocos rayos por onda, no por frame, porque
## la onda no se mueve: ver `_recortar()`.
##
## 20 sale con 2.2 grados por tramo, y ahi el recorte ya da el 70% de las celdas
## que hay con linea de vision dentro del cono. Subirlo a 32 o 48 no mejora nada
## medido: lo que queda son los escalones del recorte, no la falta de tramos.
@export_range(5, 64) var tramos: int = 20

## Rayos por tramo, repartidos por todo el ancho del tramo y con los dos bordes
## dentro, y el tramo se queda con el más corto. Marca los muros que toca el
## sonido, no sólo los que están en el centro del tramo.
##
## Subir `tramos` hace el arco más fiel pero deja huecos entre los escalones;
## esto los cierra por dentro. Con 5 el tramo mide 2.2 grados y sale a 0.56
## grados por rayo, por debajo de lo que resuelve la física (a 200 px, dos rayos
## separados un ángulo así se distinguen en 2 px), así que subirlo más sólo gasta
## rayos. Medido: con 2 muestras ya no se cuela ninguna celda con un muro de por
## medio, y con 5, 9 o 16 tampoco mejora, pero acorta el alcance. Son 5 x 20 =
## 100 rayos por onda, y sólo la primera vez: la onda no se mueve, ver
## `_recortar()`.
@export_range(2, 16) var muestras: int = 5

## Muros que ha tocado esta onda, en el orden en que los encontró el recorte.
## Puede haber más de uno: la onda no muere al primero, se para en cada dirección.
var bloques_tocados: Array[Bloque] = []
## true si esta onda se recorta contra los muros. Lo decide `_ready()` según
## quién la lanzó, así que no se exporta: no tiene sentido activarlo a mano.
var recortada: bool = false

var _elapsed : float = 0.0
var _wave_area : Area2D = null
## Distancia al primer muro en cada tramo. Vacía o `max_radius` = sin recorte.
var _distancias: PackedFloat32Array = PackedFloat32Array()
var _recortado: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Sólo las ondas de la Girl se recortan contra los muros, por el tamaño:
	# las suyas son de 1400 px y son las que develan el mapa, así que si
	# atravesaran paredes revelarían el laberinto entero de golpe y no habría
	# tensión. Las del enemigo son de 400 px y su trabajo es tantear a la
	# jugadora, así que tienen que poder pasar.
	recortada = capas_muro != 0 and capa == CAPA_ONDA_JUGADORA
	_build_wave_area()
	add_to_group(FUENTE_GROUP)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

	if _elapsed >= _total_lifetime():
		queue_free()


func _physics_process(_delta: float) -> void:
	# El recorte se calcula una vez, en el primer tick de física, y de ahí en
	# adelante es un array de radios. La onda no se mueve (es `top_level` y nace
	# donde estaba quien la lanzó) y los muros del laberinto tampoco, así que
	# repetir los rayos cada frame sería tirar rays al vacío.
	if _recortado or not recortada:
		return
	_recortar()


## true si la onda ha rozado algún muro. Ya no significa que vaya a morir: se
## queda viva y recortada. Lo consultan las pruebas y quien quiera saber si el
## sonido llegó a dar contra algo.
func ha_tocado_muros() -> bool:
	return not bloques_tocados.is_empty()


## Radio de crecimiento de la onda en este instante, sin recortar. Es el
## progreso de la animación, y es lo que usan el Pasillo y los prints.
func radio_actual() -> float:
	return _current_radius(0.0)


## Cuánto llegó realmente la onda: el tramo que más metros ha recorrido. Es el
## número que dice si el sonido sale o no de la habitación.
func radio_maximo_alcanzado() -> float:
	if not recortada or _distancias.is_empty():
		return radio_actual()
	var mayor := 0.0
	for d in _distancias:
		mayor = maxf(mayor, d)
	return minf(_current_radius(0.0), mayor)


## Radio de la onda en una dirección local, ya recortado por los muros. Quien
## tenga que decidir si un punto cae dentro (ver `SenalesTiles`) usa esto y no
## `radio_actual()`, que no sabe de paredes: con el radio sin recortar marcaría
## como visibles celdas que están detrás de un muro.
##
## `angulo_local` va en radianes y con el origen de la onda en el 0, medido
## respecto a +X local, que es hacia donde apunta.
##
## Da el radio del tramo que contiene ese ángulo, o sea cuánto ha llegado el
## sonido en esa dirección exacta. En la frontera entre dos tramos se queda corto
## si el vecino midió más largo (ahí se dibujan los dos), así que esto se queda
## corto justo en la línea de unión, que es lo prudente: markar de más sí que
## destrozaría el juego, markar de menos no.
func radio_en_direccion(angulo_local: float) -> float:
	var alcance := _current_radius(0.0)
	if not recortada or _distancias.is_empty():
		return alcance
	var medio := deg_to_rad(angulo) * 0.5
	if is_zero_approx(medio):
		return 0.0
	var t := (angulo_local + medio) / (medio * 2.0) * float(tramos)
	return _radio_tramo(clampi(int(floor(t)), 0, tramos - 1), alcance)


## Los `tramos` radios del recorte actual. Para quien quiera dibujar o medir la
## onda entera, como una prueba.
func radios() -> PackedFloat32Array:
	return _distancias.duplicate()


## ¿Está este punto del mundo dentro de la onda ahora mismo, con los muros
## puestos? La respuesta que necesita cualquiera que escuche a la Girl: por eso
## es un método de la onda y no que cada uno se monte su propia geometría.
##
## `SenalesTiles` la usa para no revelar lo que hay detrás de un muro, y el
## enemigo para no oír lo que no le ha llegado. El punto va en coordenadas del
## mundo, que es como lo tiene cualquiera que pregunta.
func alcanza(punto: Vector2) -> bool:
	var local := (punto - global_position).rotated(-global_rotation)
	return alcanza_local(local.x, local.y)


## Como `alcanza()`, pero con el punto YA en coordenadas locales de la onda:
## origen donde está la Girl y +X hacia donde apunta. Mismo test, misma
## respuesta: lo único que cambia es quién paga el giro.
##
## `SenalesTiles` recorre celda a celda el rectángulo que envuelve el cono y
## tiene que transformar cada celda al marco de la onda; hacerlo con cuatro
## productos en su propio bucle le sale muchísimo más barato que llamar a
## `alcanza()` (que además vuelve a bajar a `_current_radius` y a
## `radio_en_direccion` en cada celda). Para que el test no esté escrito en dos
## sitios, el cono entero vive aquí y `alcanza()` sólo traduce el punto.
func alcanza_local(lx: float, ly: float) -> bool:
	var alcance := _current_radius(0.0)
	if alcance <= 0.0:
		return false
	if lx < 0.0:
		return false
	var medio := deg_to_rad(angulo) * 0.5
	var a := atan2(ly, lx)
	if absf(a) > medio:
		return false
	# El mismo recorte que hace `radio_tramo`, escrito aquí para no pagar tres
	# llamadas por celda: el radio del tramo que toca, sin pasar nunca del
	# alcance de este frame.
	var radio := alcance
	if recortada and not _distancias.is_empty():
		if is_zero_approx(medio):
			radio = 0.0
		else:
			var t := (a + medio) / (medio * 2.0) * float(tramos)
			radio = minf(_distancias[clampi(int(floor(t)), 0, tramos - 1)], alcance)
	return lx * lx + ly * ly <= radio * radio


func _build_wave_area() -> void:
	_wave_area = Area2D.new()
	_wave_area.name = "WaveArea"
	_wave_area.add_to_group(AREA_GROUP)
	_wave_area.collision_layer = capa
	# monitoring = false: a la onda no le interesa detectar nada, solo que
	# otras áreas puedan detectar su forma. monitorable = true (por defecto)
	# es lo que permite que un oyente la vea. El recorte no necesita que la onda
	# detecte nada: usa rays contra el mundo, así que la máscara se queda a 0.
	_wave_area.collision_mask = 0
	_wave_area.monitoring = false
	_wave_area.monitorable = true

	# Una sola forma, el cono entero, montada una única vez. La física de la onda
	# no decide nada por sí sola: sólo avisa a los oyentes de que HAY una onda por
	# aquí, y ellos la validan después con `alcanza()` (ver `_oír_ondas()` en
	# enemigo.gd), que ya sabe del recorte. Por eso no hace falta partir el cono
	# en `tramos` polígonos ni reescribirlos con el radio de cada frame: eran
	# ~1 ms por onda viva (0.6 ms montándolos en proceso y 0.5 ms de física con
	# las formas de más) para un detalle que nadie consulta.
	var forma := ConvexPolygonShape2D.new()
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = forma
	_wave_area.add_child(col)
	forma.points = _forma_sector(max_radius)

	add_child(_wave_area)


## Un rayo por tramo contra `capas_muro`, y se guarda lo que miden. Los muros que
## sale son los que se marcan como "chocados". Con esto la onda queda recortada
## una vez y no vuelve a preguntar hasta que alguien llame a `refrescar_recorte()`.
func _recortar() -> void:
	_recortado = true
	var mundo := get_world_2d()
	if mundo == null:
		_recortado = false
		return
	var espacio := mundo.direct_space_state
	var origen := global_position
	var medio := deg_to_rad(angulo) * 0.5
	var pasos := maxi(muestras, 2)
	_distancias.resize(tramos)
	# Los muros que se marcan: uno por muro que la onda llega a tocar, y se
	# guardan todos, no sólo el del centro del tramo. Un tramo puede quedarse
	# corto por un muro que sólo está en uno de sus bordes, y ese muro también
	# se ha tocado, así que también se ilumina.
	var marcados: Dictionary = {}
	for i in range(tramos):
		# `muestras` rayos por tramo, repartidos por todo el ancho del tramo, en
		# los dos bordes incluidos, y se queda el más corto.
		#
		# El tramo se queda con el más corto porque su triángulo se dibuja con
		# ese radio en TODO el ancho del tramo, así que si el radio fuese el del
		# centro, en los bordes del tramo se estiraría más de lo que se ve. Y da
		# igual que la diferencia sea de un pelo: un rayo que va casi paralelo a la
		# cara de un muro lo cuenta como golpe y a un pelo de lado ya no, así que
		# con un solo rayo la onda se cuela por detrás de las esquinas.
		#
		# Incluyendo los bordes, dos tramos contiguos comparten rayo, así que sus
		# triángulos encajan sin dejar el hueco por el que se cuele el sonido.
		#
		# Con dos muestras ya no se cuela ninguna celda con un muro de por medio,
		# medido; con más tampoco mejora y se pierde alcance.
		var ini := -medio + (float(i) / float(tramos)) * (medio * 2.0)
		var fin := -medio + (float(i + 1) / float(tramos)) * (medio * 2.0)
		var menor := max_radius
		for j in range(pasos):
			var a := lerpf(ini, fin, float(j) / float(pasos - 1))
			var golpe := _choque(espacio, origen, a)
			var distancia: float = golpe.get("position", Vector2.ZERO).distance_to(origen) \
					if not golpe.is_empty() else max_radius
			menor = minf(menor, distancia)
			var bloque := golpe.get("collider") as Bloque
			if bloque != null and distancia < max_radius - 1.0 and not marcados.has(bloque):
				# Un mismo bloque puede salir en dos tramos seguidos: el `chocar()`
				# reinicia su cuenta atrás, que es justo lo que se quiere al tocarlo.
				marcados[bloque] = true
				bloques_tocados.append(bloque)
				bloque.chocar()
		_distancias[i] = menor


## Distancia al primer muro en una dirección local, o `max_radius` si no hay.
func _rayo(espacio: PhysicsDirectSpaceState2D, origen: Vector2, a: float) -> float:
	var golpe := _choque(espacio, origen, a)
	if golpe.is_empty():
		return max_radius
	return maxf(origen.distance_to(golpe.position as Vector2), 0.0)


## El primer cuerpo de la capa de muros en esa dirección, o un diccionario
## vacío. Se filtran los cuerpos que no sean `Bloque` por si la capa de muros se
## mezcla con otra cosa.
func _choque(espacio: PhysicsDirectSpaceState2D, origen: Vector2,
		a: float) -> Dictionary:
	# `a` es un ángulo LOCAL, el del tramo dentro de la forma, pero el rayo sale de
	# `global_position` y el espacio de físicas es el del mundo, así que el ángulo
	# lleva la rotación del nodo. Sin esto, la onda se recorta apuntando a otro
	# sitio del que ocupa: la forma girada y los rayos sin girar, y el sonido se
	# cuela por detrás de los muros. Se nota con cualquier `global_rotation` que no
	# sea cero, o sea siempre, porque la onda siempre apunta a donde mira la Girl.
	var dir := Vector2.RIGHT.rotated(a + global_rotation)
	var q := PhysicsRayQueryParameters2D.create(origen, origen + dir * max_radius)
	q.collision_mask = capas_muro
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return espacio.intersect_ray(q)


## Vuelve a lanzar los rayos. Sólo hace falta si el mapa cambia de sitio con la
## onda en el aire, que el laberinto no hace: se deja por si acaso. Los muros que
## ya se marcaron siguen con su marca puesta hasta que se apague sola.
func refrescar_recorte() -> void:
	_recortado = false
	_distancias.clear()


## El ángulo local, en el eje +X, del centro del tramo `i`.
func _angulo_tramo(i: int, medio: float) -> float:
	return -medio + ((float(i) + 0.5) / float(tramos)) * (medio * 2.0)


func _draw() -> void:
	for i in range(ring_count):
		var offset : float = i * ring_delay
		var t := (_elapsed - offset) / duration		#variable para la animación
		if t < 0.0 or t > 1.0:
			continue

		var radius : float = _current_radius(offset)
		var alpha := 1.0 - t  # se desvanece a medida que crece

		var color := color_wave
		color.a = alpha

		# Contorno del sector recortado: del centro al inicio, el borde con lo que
		# haya tapado cada muro, y de vuelta al centro. draw_polyline une puntos
		# consecutivos.
		var puntos := PackedVector2Array()
		puntos.append(Vector2.ZERO)
		puntos.append_array(_borde(radius))
		puntos.append(Vector2.ZERO)
		draw_polyline(puntos, color, line_width, true)


## El borde del cono ya recortado, en coordenadas locales y centrado en el eje
## +X (que es hacia donde apunta rotation). Recorre los mismos tramos y los mismos
## puntos que las formas de colisión, saltándose el punto que cada tramo comparte
## con el anterior, así que lo que se ve y lo que oyen son exactamente lo mismo.
func _borde(alcance: float) -> PackedVector2Array:
	var puntos := PackedVector2Array()
	for i in range(tramos):
		var arco := _arco_tramo(i, alcance)
		for k in range(0 if i == 0 else 1, arco.size()):
			puntos.append(arco[k])
	return puntos


# El polígono de la física: el vértice y el arco entero del sector. Se construye
# una vez, en `_build_wave_area()`, y ya no se toca: como el recorte no vive aquí
# (vive en `_distancias`), no hay nada que reescribir cada frame.
#
# Antes del primer tick de física no hay distancias, y tampoco las necesita quien
# no se recorta nunca, así que el cono va entero en los dos casos.
func _forma_sector(alcance: float) -> PackedVector2Array:
	var entero := PackedVector2Array([Vector2.ZERO])
	entero.append_array(_arco(alcance, 10))
	return entero


# Puntos del arco del sector, en coordenadas locales y centrado en el eje +X
# (que es hacia donde apunta rotation). Con menos segmentos que en el dibujo:
# nobody needs the collision to be pixel-perfect.
func _arco(radius: float, segmentos: int) -> PackedVector2Array:
	var medio := deg_to_rad(angulo) * 0.5
	var puntos := PackedVector2Array()
	for i in range(segmentos + 1):
		var a := -medio + (float(i) / segmentos) * (medio * 2.0)
		puntos.append(Vector2(cos(a), sin(a)) * radius)
	return puntos


# El arco del tramo `i`, un triángulo con el vértice delante: sólo los dos
# extremos del tramo, los tres puntos y nada más.
#
# Ni un punto más por tramo. Con dos o más, Godot 4.7 responde "Concave polygon
# is assigned to ConvexPolygonShape2D" y se queda con la forma anterior: al
# repartirse 45 grados entre doce tramos, cada tramo abarca 3.7 grados, y un
# punto extra parte ese arco en pasos de 1.2 grados, por debajo de lo que la
# comprobación de convexidad considera un vértice. Medido: 1 punto por tramo da
# 0 avisos, 2 dan 18 y 3 dan 36. El lisse del recorte se saca con más tramos, no
# con más puntos dentro del tramo.
#
# Un triángulo además siempre es convexo, así que la forma de colisión no puede
# depender de los radios que casualmente dé el recorte. Y no hace falta compartir
# radio en las fronteras: dos sectores que arrancan del mismo vértice cubren cada
# ángulo desde cero hasta su radio, así que en la frontera hay un escalón pero
# ningún hueco por el que se cuele nada.
func _arco_tramo(i: int, alcance: float) -> PackedVector2Array:
	var medio := deg_to_rad(angulo) * 0.5
	var ini := -medio + (float(i) / float(tramos)) * (medio * 2.0)
	var fin := -medio + (float(i + 1) / float(tramos)) * (medio * 2.0)
	var r := _radio_tramo(i, alcance)
	return PackedVector2Array([
		Vector2(cos(ini), sin(ini)) * r,
		Vector2(cos(fin), sin(fin)) * r,
	])


# El radio recortado del tramo `i`: el primer muro que hay en su dirección, o el
# alcance que le toque si no hay ninguno.
func _radio_tramo(i: int, alcance: float) -> float:
	if not recortada or _distancias.is_empty():
		return alcance
	return minf(_distancias[clampi(i, 0, tramos - 1)], alcance)


func _current_radius(offset: float) -> float:
	var t : float = clamp((_elapsed - offset) / duration , 0.0 ,1.0)
	return max_radius * _ease_out(t)


func _ease_out(t: float) -> float:
	return 1 - pow(1.0 - t, 3)

# El último anillo tarda `ring_delay` extra en terminar: hay que vivir ese tiempo
# también, o si no se corta a media expansión.
func _total_lifetime() -> float:
	return duration + max(ring_count - 1, 0) * ring_delay
