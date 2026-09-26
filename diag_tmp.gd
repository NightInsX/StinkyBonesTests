extends SceneTree

var _e: Node2D
var _t := 0.0
var _n := 0
var _prev := Vector2.ZERO
var _quiet := 0.0
var _prev_previa := Vector2.ZERO
var _mov_previa := 0.0

func _initialize() -> void:
	var s: PackedScene = load("res://node_2d.tscn")
	_escena = s.instantiate()
	root.add_child(_escena)
	_e = _escena.get_node("Enemigo")
	_prev = _e.global_position
	_prev_previa = _e.global_position

var _escena: Node2D

func _process(delta: float) -> bool:
	_t += delta
	_n += 1
	if _e.global_position.distance_to(_prev) < 0.01 and _e.velocity.length() > 1.0:
		_quiet += delta
	else:
		if _quiet > 2.0:
			print("--- se movio de nuevo tras %.1fs clavado en %s" % [_quiet, _prev])
		_quiet = 0.0
	_prev = _e.global_position
	if _n % 30 == 0:
		_mov_previa = _e.global_position.distance_to(_prev_previa)
		_prev_previa = _e.global_position
		print("t=%.2f pos=%s vel=%s atasc=%.2f mov_frame_ant=%.2f" % [
			_t, _e.global_position, _e.velocity, _e.get("_atascado"), _mov_previa])
	if _quiet > 4.0 and _n % 10 == 0:
		var col: int = _e.get_slide_collision_count()
		var txt := "colisiones=%d" % col
		for i in range(col):
			var c: KinematicCollision2D = _e.get_slide_collision(i)
			txt += " | %s n=%s pos=%s" % [c.get_collider(), c.get_normal(), c.get_position()]
		print("CLAVADO t=%.2f pos=%s vel=%s dest=%s atasc=%.2f pos_previa=%s suelo=%s %s" % [
			_t, _e.global_position, _e.velocity, _e.get("_destino"), _e.get("_atascado"),
			_e.get("_pos_previa"), _e.is_on_floor(), txt])
	return _t > 40.0
