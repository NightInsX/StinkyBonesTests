extends SceneTree

# Banco de pruebas temporal: mueve a la Girl por el mapa haciendo ruido y
# comprueba que el enemigo la persigue rodeando el muro y no se queda clavado.

const MURO := Rect2(570, 80, 480, 122)
const MEDIA_CUERPO := Vector2(72, 68)
const DURACION := 40.0

var _escena: Node2D
var _enemigo: Node2D
var _girl: Node2D
var _t: float = 0.0
var _siguiente_onda: float = 6.0
var _siguiente_movimiento: float = 0.0
var _quieto: float = 0.0
var _max_quieto: float = 0.0
var _max_quieto_paseo: float = 0.0
var _max_quieto_carga: float = 0.0
var _pos_previa: Vector2 = Vector2.ZERO
var _solapes: int = 0
var _distancias: Array[float] = []
var _cerca: int = 0


func _initialize() -> void:
	_escena = load("res://node_2d.tscn").instantiate()
	root.add_child(_escena)
	_enemigo = _escena.get_node("Enemigo")
	_girl = _escena.get_node("girl")
	_pos_previa = _enemigo.global_position
	print("[test] enemigo en ", _enemigo.global_position, " girl en ", _girl.global_position)


func _process(delta: float) -> bool:
	_t += delta

	_mover_girl(delta)
	_oyr_ruido()

	# El enemigo se considera clavado si no se mueve y no está en una de sus
	# pausas intencionadas (pausa_max = 1.8 s, se deja margen).
	var _cargando: bool = _t >= 6.0
	var movido := _enemigo.global_position.distance_to(_pos_previa)
	if movido < 0.5:
		_quieto += delta
	else:
		_quieto = 0.0
	_max_quieto = maxf(_max_quieto, _quieto)
	if _cargando:
		_max_quieto_carga = maxf(_max_quieto_carga, _quieto)
	else:
		_max_quieto_paseo = maxf(_max_quieto_paseo, _quieto)
	_pos_previa = _enemigo.global_position

	# Su cuerpo (144x136) no puede solaparse con el muro.
	var cuerpo := Rect2(
		_enemigo.global_position - MEDIA_CUERPO, MEDIA_CUERPO * 2.0
	)
	if cuerpo.intersects(MURO):
		_solapes += 1

	var d := _enemigo.global_position.distance_to(_girl.global_position)
	_distancias.append(d)
	if d < 170.0:
		_cerca += 1

	if _t >= DURACION:
		_resumen()
		return true
	return false


func _mover_girl(delta: float) -> void:
	_siguiente_movimiento -= delta
	if _siguiente_movimiento > 0.0:
		return
	_siguiente_movimiento = 2.0
	# Se pasea por todo el mapa, también al otro lado del muro.
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

	var escena_onda: PackedScene = load("res://scenes/echo.tscn")
	var onda: Node2D = escena_onda.instantiate()
	onda.capa = 2  # CAPA_ONDA_JUGADORA
	onda.max_radius = 500.0
	onda.duration = 0.6
	_girl.add_child(onda)
	onda.top_level = true
	onda.global_position = _girl.global_position
	# Apunta al enemigo, que si no el cono de 45 grados puede no oírla nunca.
	onda.rotation = (_enemigo.global_position - _girl.global_position).angle()


func _resumen() -> void:
	var media := 0.0
	for d in _distancias:
		media += d
	media /= maxf(1.0, _distancias.size())
	print("---- RESULTADO ----")
	print("tiempo clavado maximo paseando: %.2f s (limite 4.0)" % _max_quieto_paseo)
	print("tiempo clavado maximo persiguiendo: %.2f s (limite 4.0)" % _max_quieto_carga)
	print("frames con el cuerpo dentro del muro: %d (limite 0)" % _solapes)
	print("distancia media enemigo-girl: %.0f px" % media)
	print("frames a menos de 170 px: %d" % _cerca)
	var mal := _max_quieto_paseo > 4.0 or _max_quieto_carga > 4.0 or _solapes > 0
	print("VEREDICTO: ", "FALLO" if mal else "OK")
