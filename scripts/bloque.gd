class_name Bloque
extends StaticBody2D

## Bit 3 de la máscara de capas. Los muros viven en una capa propia, separados de
## la de los personajes, y las dos se declaran aquí porque el bloque es el dueño
## del muro: las usa `DTLMapa` al construirlos y `Echo` al recortar el cono
## contra ellos.
const CAPA_MURO := 8  # bit 3
## Bit 0 de la máscara de capas. La Girl y el enemigo.
const CAPA_PERSONAJE := 1  # bit 0

# Bloque de muro del mapa. Guarda si una onda de la Girl acaba de chocar contra
# él, y esa marca se apaga sola pasado un tiempo.
#
# El mapa se pinta fusionando celdas de muro en rectángulos (ver
# `_particionar`), así que un bloque es un rectángulo de NxM celdas, no una
# celda. Por eso hay un bloque por rectángulo y no un muro único con la bandera
# puesta a tiro: con un solo cuerpo, un chocado en la esquina norte del mapa
# encendería el "chocado" de los muros del sur.
#
# La marca no es un adorno: el muro se ilumina mientras está chocado, para que se
# vea por dónde fue el sonido y por dónde choca. Se pinta en `_draw()` y hay que
# avisar con `queue_redraw()` en cuanto cambia el estado, porque un CanvasItem
# sólo dibuja desde dentro del árbol.

## Se emite al chocar una onda, con los segundos que dura la marca.
signal impactado(duracion: float)

## Cuánto tiempo `chocado` se queda en true. Pasado ese plazo se pone solo en
## false, con la cuenta atrás que lleva el propio bloque y que sólo corre
## mientras la marca está puesta.
@export_range(0.1, 10.0, 0.1) var duracion_chocado: float = 1.5

## Color de la forma del muro cuando no está chocado.
@export var color_muro := Color(0.13, 0.12, 0.16)

## Color de la forma mientras `chocado` está en true.
@export var color_chocado := Color(0.55, 0.95, 1.0)

## Marca de bloque "sensible". Se pinta EXACTAMENTE igual que el resto en
## reposo (mismo `color_muro`, mismo borde), así que en el mapa no se distingue
## de un muro normal: sólo cambia lo que hace cuando le llega la onda de la
## Girl, que lo enciende en rojo en vez de en azul. La decide la generación del
## mapa al construir los bloques, no se toca a mano durante la partida.
@export var sensible: bool = false

## Color de la forma mientras `chocado` está en true, cuando `sensible` está
## puesto. El rojo es el aviso de que este trozo de muro no es uno cualquiera.
@export var color_chocado_sensible := Color(1.0, 0.3, 0.24)

## Intensidad de la marca, de 0 a 1. Se interpola con `tiempo_restante()` para
## que el muro se apague a medida que se acaba el plazo, en vez de cortar en seco.
@export_range(0.0, 1.0, 0.05) var intensidad_chocado: float = 0.85

## true entre el impacto y `duracion_chocado` segundos después.
var chocado: bool = false

## Segundos que quedan de marca, con su propio contador en vez de un
## `SceneTreeTimer` por impacto. Ver `chocar()`.
var _restante: float = 0.0


func _ready() -> void:
	# Un bloque sin marca no tiene nada que hacer cada frame. Un laberinto tiene
	# del orden de trescientos muros y casi ninguno choca nunca, y tenerlos a
	# todos despiertos costaba ~0.2 ms por frame: el que choca se despierta solo,
	# en `chocar()`, y se vuelve a dormir en `_apagar()`.
	set_process(false)


## Marca el chocado y programa su apagado. Si el bloque ya estaba chocado, el
## plazo se reinicia: chocar dos veces seguidas deja la marca puesta más rato,
## que es justo lo que quiere quien esté leyendo el booleano.
func chocar() -> void:
	chocado = true
	_restante = duracion_chocado
	set_process(true)
	queue_redraw()
	impactado.emit(duracion_chocado)


## Cuánto le queda para apagarse, o 0 si no está chocado. Para quien quiera
## algo más fino que true/false, como una barra que se vacía.
func tiempo_restante() -> float:
	if not chocado:
		return 0.0
	return maxf(_restante, 0.0)


func _apagar() -> void:
	chocado = false
	_restante = 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	# Sólo está despierto mientras la marca está puesta (ver `_ready()`), así que
	# aquí no hace falta comprobarlo. El último medio segundo se repinta más a
	# menudo para que la disolución no dé saltos.
	_restante -= delta
	if _restante <= 0.0:
		_apagar()
		return
	if _restante <= 0.5:
		queue_redraw()


## Pinta el rectángulo de muro con el color que le toca. No se toca la física ni
## se recolorea la forma: el muro es una mancha negra sobre el suelo, y encima se
## dibuja el mismo rectángulo con el color del estado. Dibujarlo aquí en vez de
## usar `CollisionShape2D.draw()` es a propósito, porque ese método no existe en
## todas las versiones de Godot 4 y el rectángulo sale directamente del hijo.
func _draw() -> void:
	for hijo in get_children():
		if not hijo is CollisionShape2D:
			continue
		var col := hijo as CollisionShape2D
		var rect := col.shape.get_rect() if col.shape != null else Rect2()
		rect.position += col.position
		draw_rect(rect, _color_actual(), true)
		# Una línea del color del suelo alrededor para que el muro se lea como
		# hueco y no como una plancha de color, que es como está pintado el mapa.
		draw_rect(rect, color_muro, false, 2.0)


## El color que le toca ahora mismo: el normal, o el de chocado fading out con
## lo que le queda de plazo. Cuando ya no queda nada vuelve al normal, así que el
## final de la marca no tiene salto de color. Los sensibles usan su rojo, los
## demás el azul: en reposo los dos son indistinguibles.
func _color_actual() -> Color:
	if not chocado:
		return color_muro
	var vida := 1.0
	if duracion_chocado > 0.0:
		vida = clampf(_restante / duracion_chocado, 0.0, 1.0)
	var encendido := color_chocado_sensible if sensible else color_chocado
	return color_muro.lerp(encendido, intensidad_chocado * vida)
