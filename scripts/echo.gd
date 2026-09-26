class_name Echo
extends Node2D

# La onda NO busca cuerpos: solo lleva un Area2D cuyo radio crece.
# Cada objeto que quiera "oírla" se suscribe con su propio Area2D
# (ver scripts/pasillo.gd), así que no hace falta ninguna lista de cuerpos
# detectados aquí ni conectar señales a mano.
const AREA_GROUP := "echo_onda"

@export var max_radius : float = 200.0
@export var duration:float = 1
@export var ring_count = 2
@export var ring_delay = 0.1
@export var color_wave :Color = Color(1.0, 1.0, 1.0)
@export var line_width = 3
var _elapsed : float = 0.0
var _wave_area : Area2D = null
var _wave_shape : CircleShape2D = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_build_wave_area()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

	_wave_shape.radius = _current_radius(0.0)

	if _elapsed >= _total_lifetime():
		queue_free()


# Radio de la onda en este instante. Quien la detecte puede consultarlo
# para decidir si le ha alcanzado.
func radio_actual() -> float:
	return _current_radius(0.0)


func _build_wave_area() -> void:
	_wave_shape = CircleShape2D.new()
	_wave_shape.radius = 0.0

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = _wave_shape

	_wave_area = Area2D.new()
	_wave_area.name = "WaveArea"
	_wave_area.add_to_group(AREA_GROUP)
	# monitoring = false: a la onda no le interesa detectar nada, solo que
	# otras áreas puedan detectar su forma. monitorable = true (por defecto)
	# es lo que permite que un pasillo la vea.
	_wave_area.monitoring = false
	_wave_area.monitorable = true
	_wave_area.add_child(collision)

	add_child(_wave_area)


func _draw() -> void:
	for i in range(ring_count):
		var offset : float = i * ring_delay
		var t := (_elapsed - offset) / duration
		if t < 0.0 or t > 1.0:
			continue

		var radius : float = _current_radius(offset)
		var alpha := 1.0 - t  # se desvanece a medida que crece

		var color := color_wave
		color.a = alpha

		_draw_circle_outline(radius, color, line_width)


func _draw_circle_outline(radius: float, color: Color, width: float) -> void:
	# Calcula los puntos del círculo a mano y los une con draw_polyline().
	# No depende de draw_arc(), así que funciona en cualquier versión.
	var points := PackedVector2Array()
	var segments := 48

	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	draw_polyline(points, color, width, true)


func _current_radius(offset: float) -> float:
	var t : float = clamp((_elapsed - offset) / duration , 0.0 ,1.0)
	return max_radius * _ease_out(t)


func _ease_out(t: float) -> float:
	return 1 - pow(1.0 - t, 3)

# El último anillo tarda `ring_delay` extra en terminar: hay que vivir ese tiempo
# también, o si no se corta a media expansión.
func _total_lifetime() -> float:
	return duration + max(ring_count - 1, 0) * ring_delay
