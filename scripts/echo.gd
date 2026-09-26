class_name Echo
extends Node2D

# Onda cónica: un sector que se abre `angulo` grados y apunta en la
# dirección de rotation (la del ratón en el momento de lanzarla).
#
# La onda NO busca cuerpos: solo lleva un Area2D cuya forma crece. Cada
# objeto que quiera "oírla" se suscribe con su propio Area2D (ver
# scripts/pasillo.gd), así que no hace falta ninguna lista de cuerpos
# detectados aquí ni conectar señales a mano.
const AREA_GROUP := "echo_onda"

# Capas de colisión: deciden quién oye a quién. Quien lanza la onda elige en
# qué capa la mete, y cada oyente pone en su máscara las capas que le
# interesan. Así el filtrado lo hace la física y ningún script tiene que
# descartar ondas ajenas a mano.
const CAPA_ONDA_JUGADORA := 2  # bit 2: la oye la Girl y el Pasillo
const CAPA_ONDA_ENEMIGA := 4  # bit 3: solo la oye la Girl

@export var max_radius : float = 200.0 #Radio si se necesita se aumenta
@export var duration:float = 1 #duracion en pantalla
@export var ring_count = 2	#puramente cosmetico
@export var ring_delay = 0.1
@export var color_wave :Color = Color(1.0, 1.0, 1.0)
@export var line_width = 3
@export var angulo : float = 45.0  # apertura del cono, en grados
@export var capa : int = 1  # en qué collision_layer se mete la onda
var _elapsed : float = 0.0
var _wave_area : Area2D = null
var _wave_shape : ConvexPolygonShape2D = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_build_wave_area()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

	_wave_shape.points = _forma_cono(_current_radius(0.0))

	if _elapsed >= _total_lifetime():
		queue_free()


# Radio de la onda en este instante. Quien la detecte puede consultarlo
# para decidir si le ha alcanzado.
func radio_actual() -> float:
	return _current_radius(0.0)


func _build_wave_area() -> void:
	_wave_shape = ConvexPolygonShape2D.new()

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = _wave_shape

	_wave_area = Area2D.new()
	_wave_area.name = "WaveArea"
	_wave_area.add_to_group(AREA_GROUP)
	_wave_area.collision_layer = capa
	_wave_area.collision_mask = 0
	# monitoring = false: a la onda no le interesa detectar nada, solo que
	# otras áreas puedan detectar su forma. monitorable = true (por defecto)
	# es lo que permite que un oyente la vea.
	_wave_area.monitoring = false
	_wave_area.monitorable = true
	_wave_area.add_child(collision)

	add_child(_wave_area)


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

		# Contorno del sector: del centro al inicio del arco, el arco, y de
		# vuelta al centro. draw_polyline une puntos consecutivos.
		var puntos := PackedVector2Array()
		puntos.append(Vector2.ZERO)
		puntos.append_array(_arco(radius, 10))
		puntos.append(Vector2.ZERO)
		draw_polyline(puntos, color, line_width, true)


# Puntos del arco del sector, en coordenadas locales y centrado en el eje +X
# (que es hacia donde apunta rotation). Lo usan tanto el dibujo como la forma
# de colisión, así que lo que se ve y lo que detecta el pasillo son
# exactamente la misma cosa.
func _arco(radius: float, segmentos: int) -> PackedVector2Array:
	var medio := deg_to_rad(angulo) * 0.5
	var puntos := PackedVector2Array()
	for i in range(segmentos + 1):
		var a := -medio + (float(i) / segmentos) * (medio * 2.0)
		puntos.append(Vector2(cos(a), sin(a)) * radius)
	return puntos


# El cono como polígono convexo, para la física. Con menos segmentos que en
# el dibujo: nobody needs the collision to be pixel-perfect.
func _forma_cono(radius: float) -> PackedVector2Array:
	var puntos := PackedVector2Array()
	puntos.append(Vector2.ZERO)
	puntos.append_array(_arco(radius, 4))
	return puntos


func _current_radius(offset: float) -> float:
	var t : float = clamp((_elapsed - offset) / duration , 0.0 ,1.0)
	return max_radius * _ease_out(t)


func _ease_out(t: float) -> float:
	return 1 - pow(1.0 - t, 3)

# El último anillo tarda `ring_delay` extra en terminar: hay que vivir ese tiempo
# también, o si no se corta a media expansión.
func _total_lifetime() -> float:
	return duration + max(ring_count - 1, 0) * ring_delay
