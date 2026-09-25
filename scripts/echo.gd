extends Node2D

signal wave_reached(body: Node2D)

@export var max_radius : float = 200.0
@export var duration:float = 1
@export var ring_count = 2
@export var ring_delay = 0.1
@export var color_wave :Color = Color(1.0, 1.0, 1.0)
@export var line_width = 3
@export var emit_detection_signal : bool = true
var _elapsed : float = 0.0
var _detection_area : Area2D = null
var _detected_bodies: Array = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if emit_detection_signal:
		_set_up_detection_area()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
 
	if _detection_area:
		var shape := _detection_area.get_node("CollisionShape2D").shape as CircleShape2D
		shape.radius = _current_radius(0.0)
		
	if _elapsed >= _total_lifetime():
		queue_free()


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

func _set_up_detection_area() -> void:
	_detection_area = Area2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 0.0
	
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.name = "CollisionShape2D"
	
	_detection_area.add_child(collision)
	add_child(_detection_area)
	
	_detection_area.body_entered.connect(_on_body_entered)
	
	
func _on_body_entered(body : Node2D) -> void:
	if body in _detected_bodies:
		return
	_detected_bodies.append(body)
	wave_reached.emit(body)
	
		
		
