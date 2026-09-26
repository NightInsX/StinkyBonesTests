extends SceneTree

# Diagnostico: mide cuanto tiempo el enemigo empuja contra un cuerpo solido
# (muro) sin conseguir avanzar. Eso es el sintoma de "quedarse atascado".

const DURACION := 40.0
const PRESION_MIN := 0.35

var _enemigo: CharacterBody2D
var _girl: Node2D
var _t: float = 0.0
var _pos_previa: Vector2 = Vector2.ZERO
var _presion: float = 0.0
var _max_presion: float = 0.0
var _max_presion_pos: Vector2 = Vector2.ZERO
var _racha_actual: float = 0.0
var _siguiente_movimiento: float = 0.0
var _siguiente_onda: float = 6.0
var _total_presion: float = 0.0
var _frames: int = 0
var _muros: Array[String] = []


func _initialize() -> void:
	var packed: PackedScene = load("res://node_2d.tscn")
	var escena: Node2D = packed.instantiate()
	root.add_child(escena)
	_enemigo = escena.get_node("Enemigo")
	_girl = escena.get_node("girl")
	_pos_previa = _enemigo.global_position


func _process(delta: float) -> bool:
	_t += delta
	_frames += 1
	_mover_girl(delta)
	_oyr_ruido()

	var empujando := false
	var nombres: Array[String] = []
	for i in _enemigo.get_slide_collision_count():
		var col := _enemigo.get_slide_collision(i)
		var n := col.get_normal()
		if n.dot(_enemigo.velocity) < -1.0:
			empujando = true
			var c := col.get_collider()
			nombres.append("%s@%s" % [c.name, str((c as Node2D).global_position.round())])

	if empujando:
		_presion += delta
		_total_presion += delta
		# Solo cuenta si ademas no avanza: rozar un muro mientras se pasa no es
		# quedarse atascado.
		if _enemigo.global_position.distance_to(_pos_previa) < 0.35:
			_racha_actual += delta
			if _racha_actual > _max_presion:
				_max_presion = _racha_actual
				_max_presion_pos = _enemigo.global_position
				_muros = nombres
		else:
			_racha_actual = 0.0
	else:
		_racha_actual = 0.0
	_presion = 0.0 if not empujando else _presion
	_pos_previa = _enemigo.global_position

	if _t >= DURACION:
		_resumen()
		return true
	return false


func _mover_girl(_delta: float) -> void:
	_siguiente_movimiento -= 1.0 / 60.0
	if _siguiente_movimiento > 0.0:
		return
	_siguiente_movimiento = 2.0
	var puntos := [
		Vector2(120, 560), Vector2(1000, 560), Vector2(1000, 60),
		Vector2(700, 60), Vector2(700, 560), Vector2(587, 488),
	]
	_girl.global_position = puntos[randi() % puntos.size()]


func _oyr_ruido() -> void:
	_siguiente_onda -= 1.0 / 60.0
	if _siguiente_onda > 0.0:
		return
	_siguiente_onda = 1.5
	var onda: Node2D = load("res://scenes/echo.tscn").instantiate()
	onda.capa = 2
	onda.max_radius = 500.0
	onda.duration = 0.6
	_girl.add_child(onda)
	onda.top_level = true
	onda.global_position = _girl.global_position
	onda.rotation = (_enemigo.global_position - _girl.global_position).angle()


func _resumen() -> void:
	print("---- DIAG PRESION ----")
	print("racha maxima clavado empujando un muro: %.2f s" % _max_presion)
	print("  en la posicion: ", _max_presion_pos)
	print("  contra: ", _muros)
	print("tiempo total con el cuerpo contra un muro: %.2f s de %.1f s" % [_total_presion, _t])
	print("porcentaje de frames clavado: %.1f%%" % (100.0 * _max_presion / _t))
	print("VEREDICTO: ", "FALLO" if _max_presion > PRESION_MIN else "OK")
