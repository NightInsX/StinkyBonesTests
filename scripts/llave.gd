class_name Llave
extends Area2D

# Objeto que se recoge al tocarlo, sin botón: basta con pasar por encima. Al
# recogerlo le pone la llave a la jugadora y se esconde.
#
# No sabe que existe una puerta ni la busca. La puerta es la que mira si la
# jugadora la lleva, así que añadir otro objeto que abra algo no obliga a tocar
# nada aquí.

## Se emite al recogerla, por si hay que hacer algo más (un ruido, un efecto).
signal recogida(posicion: Vector2)

## La jugadora. Hace falta comprobar quién es porque un Area2D avisa de CUALQUIER
## CharacterBody2D que lo toque, y en el mapa están la Girl y el enemigo.
@export var nodo_jugadora: NodePath = ^"../girl"
## En qué celda del mapa está puesta. Lo usa Puerta y las pruebas, no el juego.
@export var celda: Vector2i = Vector2i(-1, -1)

var _recogida: bool = false


func _ready() -> void:
	body_entered.connect(_on_cuerpo_entered)
	# Si aparece la llave justo encima de la jugadora, `body_entered` no se
	# dispara: Godot sólo avisa de los cuerpos que ENTRAN. Esto se comprueba un
	# frame después, cuando ya se ha hecho la física y hay solapes fiables.
	call_deferred("_comprobar_solape")


func esta_recogida() -> bool:
	return _recogida


## Vuelve a dejarla en el sitio, como al empezar una partida nueva.
func reponer() -> void:
	_recogida = false
	visible = true
	monitoring = true
	var jugadora := _jugadora()
	if jugadora != null:
		jugadora.tiene_llave = false


func _on_cuerpo_entered(cuerpo: Node2D) -> void:
	_recoger_si_es(cuerpo)


func _comprobar_solape() -> void:
	for cuerpo in get_overlapping_bodies():
		_recoger_si_es(cuerpo as Node2D)
		if _recogida:
			return


func _recoger_si_es(cuerpo: Node2D) -> void:
	if _recogida or cuerpo == null:
		return
	var jugadora := _jugadora()
	if jugadora == null or cuerpo != jugadora:
		return
	_recogida = true
	jugadora.tiene_llave = true
	# Se esconde en lugar de liberarse: si se libera, el nodo desaparece y se
	# lleva por delante las conexiones que le haya hecho cualquiera.
	visible = false
	# Con `set_deferred` y no directo: esto se ejecuta dentro del aviso de
	# `body_entered`, y Godot no deja tocar `monitoring` mientras está
	# notific colliding bodies. Si se fuerza, salta un error por consola y la
	# llave SEGUIRIA detectando a la jugadora aunque parezca escondida.
	set_deferred("monitoring", false)
	recogida.emit(global_position)
	print("[llave] recogida en ", celda, ". La puerta ya se puede abrir.")


func _jugadora() -> Node2D:
	return get_node_or_null(nodo_jugadora) as Node2D
