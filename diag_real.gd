extends SceneTree

# Diagnostico realista: la Girl se teletransporta solo a puntos donde SU
# cuerpo cabe de verdad (105x105, hueco del pasillo 90px), y se mide cuanto
# tarda el enemigo (144x136) en llegar y cuanto se queda clavado.

# Puntos validos para la Girl: x <= 516, x >= 1100, y <= 32 o y >= 258.
const CASOS := [
	{"nombre": "main centro", "girl": Vector2(820, 400), "enemigo": Vector2(150, 120)},
	{"nombre": "main derecha", "girl": Vector2(1000, 550), "enemigo": Vector2(150, 120)},
	{"nombre": "main abajo centro", "girl": Vector2(600, 600), "enemigo": Vector2(150, 120)},
	{"nombre": "izquierda", "girl": Vector2(150, 400), "enemigo": Vector2(1000, 500)},
	{"nombre": "arriba izquierda", "girl": Vector2(200, 20), "enemigo": Vector2(900, 500)},
	{"nombre": "derecha del pasillo", "girl": Vector2(1120, 400), "enemigo": Vector2(150, 400)},
	{"nombre": "esquina inf izq", "girl": Vector2(60, 620), "enemigo": Vector2(1050, 600)},
	{"nombre": "cruce de ida y vuelta", "girl": Vector2(950, 300), "enemigo": Vector2(300, 600)},
]

const DURACION := 15.0
const DIST_OK := 150.0

var _i: int = 0
var _t: float = 0.0
var _escena: Node2D
var _enemigo: CharacterBody2D
var _girl: Node2D
var _pos_previa: Vector2
var _racha: float = 0.0
var _max_racha: float = 0.0
var _max_pos: Vector2
var _muros: Array[String] = []
var _min_dist: float = 1e9
var _llego: bool = false
var _tiempo_llegada: float = -1.0


func _initialize() -> void:
	_arrancar()


func _process(delta: float) -> bool:
	_t += delta
	_ruido()
	_medir(delta)
	if _t >= DURACION:
		_resumen()
		_i += 1
		if _i < CASOS.size():
			_arrancar()
		else:
			print("---- FIN ----")
			return true
	return false


func _arrancar() -> void:
	var packed: PackedScene = load("res://node_2d.tscn")
	var escena: Node2D = packed.instantiate()
	root.add_child(escena)
	_enemigo = escena.get_node("Enemigo")
	_girl = escena.get_node("girl")
	var c: Dictionary = CASOS[_i]
	_enemigo.global_position = c["enemigo"]
	_girl.global_position = c["girl"]
	_pos_previa = _enemigo.global_position
	_racha = 0.0
	_max_racha = 0.0
	_t = 0.0
	_min_dist = 1e9
	_llego = false
	_tiempo_llegada = -1.0
	print("\n===== CASO %d: %s =====" % [_i, c["nombre"]])


func _ruido() -> void:
	if fmod(_t, 1.2) >= 1.0 / 60.0:
		return
	var onda: Node2D = load("res://scenes/echo.tscn").instantiate()
	onda.capa = 2
	onda.max_radius = 500.0
	onda.duration = 0.6
	_girl.add_child(onda)
	onda.top_level = true
	onda.global_position = _girl.global_position
	onda.rotation = (_enemigo.global_position - _girl.global_position).angle()


func _medir(delta: float) -> void:
	var empujando := false
	var nombres: Array[String] = []
	for i in _enemigo.get_slide_collision_count():
		var col := _enemigo.get_slide_collision(i)
		if col.get_normal().dot(_enemigo.velocity) < -1.0:
			empujando = true
			nombres.append(str(col.get_collider().name))
	var quieto := _enemigo.global_position.distance_to(_pos_previa) < 0.35
	if empujando and quieto:
		_racha += delta
		if _racha > _max_racha:
			_max_racha = _racha
			_max_pos = _enemigo.global_position
			_muros = nombres
	elif not empujando or not quieto:
		_racha = 0.0
	_pos_previa = _enemigo.global_position

	var d := _enemigo.global_position.distance_to(_girl.global_position)
	_min_dist = minf(_min_dist, d)
	if not _llego and d <= DIST_OK:
		_llego = true
		_tiempo_llegada = _t


func _resumen() -> void:
	print("  llega a <=%.0f px: %s" % [DIST_OK, ("si, en %.1f s" % _tiempo_llegada) if _llego else "NO"])
	print("  distancia minima: %.0f px" % _min_dist)
	print("  racha maxima clavado: %.2f s en %s contra %s" % [_max_racha, _max_pos, _muros])
	print("  VEREDICTO: ", "ATASCADO" if (_max_racha > 1.5 or not _llego) else "OK")
