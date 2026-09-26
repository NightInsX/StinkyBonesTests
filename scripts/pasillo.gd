extends Area2D

#este pasillo es el que detecta que la onda le llegua y que el personaje no esta muy lejos


@export var umbral : float = 0.35	#umbral para que no detecte la onda muy lejos

@export var color_activado : Color = Color(0.6, 1.3, 0.8)

var detectado : bool = false
var _onda : Echo = null


func _ready() -> void:
	# Solo oye las ondas que lanza la jugadora. Las del enemigo van en otra
	# capa, así que ni siquiera le llegan por aquí.
	collision_mask = Echo.CAPA_ONDA_JUGADORA
	area_entered.connect(_on_area_entered)
	_pintar(false)


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group(Echo.AREA_GROUP):
		return
	_onda = area.get_parent() as Echo
	if _onda == null:
		return
	print("[pasillo] overlap con onda nacida en ", _onda.global_position)


func _process(_delta: float) -> void:
	# La onda se libera a los ~0.7 s; is_instance_valid es más fiable que
	# area_exited para enterarse.
	if _onda != null and not is_instance_valid(_onda):
		_onda = null
	_set_detectado(_onda != null and detectar_onda(_onda))


# La detección es booleana: o la onda ha crecido lo bastante para llegar
# al pasillo, o todavía no.
func detectar_onda(onda: Echo) -> bool:
	return onda.radio_actual() / max(onda.max_radius, 0.001) >= umbral


# Solo imprime cuando el booleano cambia, para no saturar la consola.
func _set_detectado(valor: bool) -> void:
	if valor == detectado:
		return
	detectado = valor
	_pintar(valor)
	if valor:
		print("[pasillo] RECIBIDA   ", _estado())
	else:
		print("[pasillo] NO OYENDO   ", _estado())


func _estado() -> String:
	if _onda == null or not is_instance_valid(_onda):
		return "sin onda | umbral=%.2f" % umbral
	return "onda en %s radio=%.1f/%.0f umbral=%.2f" % [
		_onda.global_position, _onda.radio_actual(), _onda.max_radius, umbral
	]


func _pintar(activado: bool) -> void:
	modulate = color_activado if activado else Color.WHITE
