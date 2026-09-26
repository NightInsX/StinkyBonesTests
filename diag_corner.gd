extends SceneTree

# Diagnostico por escenarios: cada caso coloca a la Girl donde el enemigo
# tiene que rodear el pasillo o meterse por un hueco mas estrecho que su
# cuerpo, que es cuando se queda clavado.

const ESCENARIOS := [
	{"nombre": "girl al otro lado del pasillo (arriba dcha)", "girl": Vector2(1000, 60), "enemigo": Vector2(200, 500)},
	{"nombre": "girl al otro lado del pasillo (arriba centro)", "girl": Vector2(700, 60), "enemigo": Vector2(200, 500)},
	{"nombre": "girl en la boca del pasillo", "girl": Vector2(600, 145), "enemigo": Vector2(950, 500)},
	{"nombre": "girl en la boca del pasillo (otro lado)", "girl": Vector2(1050, 145), "enemigo": Vector2(150, 300)},
	{"nombre": "girl en el pasillo hacia dentro", "girl": Vector2(800, 145), "enemigo": Vector2(200, 400)},
]

const DURACION := 18.0


func _initialize() -> void:
	_run(0)


func _process(delta: float) -> bool:
	var d: float = get_meta("t", 0.0) + delta
	set_meta("t", d)
	_ruido(delta)
	if d >= DURACION:
		_resumen(d)
		if int(get_meta("i", 0)) + 1 < ESCENARIOS.size():
			var i: int = int(get_meta("i")) + 1
			_run(i)
			return false
		print("---- FIN ----")
		return true
	return false


var _enemigo: CharacterBody2D
var _girl: Node2D
var _pos_previa: Vector2
var _racha: float
var _max_racha: float
var _max_pos: Vector2
var _muros: Array[String] = []


func _run(i: int) -> void:
	var packed: PackedScene = load("res://node_2d.tscn")
	var escena: Node2D = packed.instantiate()
	root.add_child(escena)
	_enemigo = escena.get_node("Enemigo")
	_girl = escena.get_node("girl")
	var c: Dictionary = ESCENARIOS[i]
	_enemigo.global_position = c["enemigo"]
	_girl.global_position = c["girl"]
	# El enemigo arranca pegado al muro del pasillo, que es donde se atasca.
	_pos_previa = _enemigo.global_position
	_racha = 0.0
	_max_racha = 0.0
	set_meta("t", 0.0)
	set_meta("i", i)
	print("\n===== CASO %d: %s =====" % [i, c["nombre"]])
	print("  enemigo ", _enemigo.global_position, "  girl ", _girl.global_position,
		"  dist=%.0f" % _enemigo.global_position.distance_to(_girl.global_position))


func _ruido(_delta: float) -> void:
	var t: float = get_meta("t", 0.0)
	if fmod(t, 1.0) < 1.0 / 60.0:
		_girl.get_parent().get_node("girl")  # no-op, keeps tree alive
		var onda: Node2D = load("res://scenes/echo.tscn").instantiate()
		onda.capa = 2
		onda.max_radius = 500.0
		onda.duration = 0.6
		_girl.add_child(onda)
		onda.top_level = true
		onda.global_position = _girl.global_position
		onda.rotation = (_enemigo.global_position - _girl.global_position).angle()

	var empujando := false
	var nombres: Array[String] = []
	for i in _enemigo.get_slide_collision_count():
		var col := _enemigo.get_slide_collision(i)
		if col.get_normal().dot(_enemigo.velocity) < -1.0:
			empujando = true
			var c := col.get_collider()
			nombres.append(str(c.name))
	if empujando and _enemigo.global_position.distance_to(_pos_previa) < 0.35:
		_racha += 1.0 / 60.0
		if _racha > _max_racha:
			_max_racha = _racha
			_max_pos = _enemigo.global_position
			_muros = nombres
	elif not empujando or _enemigo.global_position.distance_to(_pos_previa) >= 0.35:
		_racha = 0.0
	_pos_previa = _enemigo.global_position


func _resumen(d: float) -> void:
	var dist := _enemigo.global_position.distance_to(_girl.global_position)
	print("  resultado: enemigo en ", _enemigo.global_position,
		"  dist final=%.0f" % dist)
	print("  racha maxima clavado: %.2f s en %s contra %s"
		% [_max_racha, _max_pos, _muros])
	var mal := _max_racha > 1.0
	print("  VEREDICTO: ", "ATASCADO" if mal else "OK")
