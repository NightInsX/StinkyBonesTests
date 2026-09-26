class_name Puerta
extends Area2D

# Puerta de salida del laberinto. Está cerrada hasta que la jugadora lleva la
# llave, y al tocarla con la llave puesta se abre y se gana la partida.
#
# No lleva ningún cuerpo de colisión propio, y a propósito. Lo que hay detrás es
# el marco del mapa, así que la puerta no tapona ningún paso: es un biombo, no
# una barrera. Lo único que hace falta es enterarse de que la jugadora ha
# llegado, y para eso está su Area2D.
#
# El juego no tiene ninguna interfaz, así que ganar se anuncia con una señal
# `victoria` y un print. Quien quiera poner una pantalla de victoria, o música, o
# un contador de tiempo, se conecta a la señal.

## Se gana la partida.
signal victoria(celda: Vector2i)
## Se emite al abrirse, antes que `victoria`, por si hay que distinguir abrir de
## ganar (un tutorial, por ejemplo, que no debería dar la partida por buena).
signal abierta(celda: Vector2i)
## La jugadora ha llegado sin llave. Sirve para avisarla por si aparece otra vez.
signal rechazada(celda: Vector2i)

@export var nodo_jugadora: NodePath = ^"../girl"
## En qué celda del mapa está puesta. Lo usan las pruebas y el print.
@export var celda: Vector2i = Vector2i(-1, -1)
@export var color_cerrada: Color = Color(0.62, 0.16, 0.18)
@export var color_abierta: Color = Color(0.35, 0.92, 0.55)
@export var texto_sin_llave: String = "Cerrada. Falta algo por encontrar."

var _abierta: bool = false


func _ready() -> void:
	body_entered.connect(_on_cuerpo_entered)
	_pintar()


func esta_abierta() -> bool:
	return _abierta


## La vuelve a cerrar y, con ella, la partida.
func reponer() -> void:
	_abierta = false
	_pintar()


func _on_cuerpo_entered(cuerpo: Node2D) -> void:
	if _abierta or cuerpo == null:
		return
	var jugadora := _jugadora()
	if jugadora == null or cuerpo != jugadora:
		return

	if not jugadora.tiene_llave:
		rechazada.emit(celda)
		print("[puerta] ", celda, ": ", texto_sin_llave)
		return

	_abierta = true
	_pintar()
	abierta.emit(celda)
	print("[puerta] abierta en ", celda, " -> ¡partida ganada!")
	victoria.emit(celda)


func _jugadora() -> Node2D:
	return get_node_or_null(nodo_jugadora) as Node2D


func _pintar() -> void:
	var hoja := get_node_or_null("Hoja") as Polygon2D
	if hoja != null:
		hoja.color = color_abierta if _abierta else color_cerrada
	for nombre in ["MarcoSup", "MarcoInf"]:
		var marco := get_node_or_null(nombre) as Polygon2D
		if marco != null:
			marco.color.a = 0.5 if _abierta else 1.0
