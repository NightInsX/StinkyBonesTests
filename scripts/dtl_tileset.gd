class_name DTLTileSet
extends RefCounted

# Construye el TileSet del mapa proceduralmente, sin depender de texturas externas.
#
# El atlas tiene 4 columnas x 3 filas de teselas de `tile_size`:
#   fila 0 -> suelo (4 variantes)
#   fila 1 -> muro  (4 variantes)
#   fila 2 -> umbral/puerta (4 variantes, la primera es la lisa)

const COLUMNAS := 4
const FILAS := 3
const SUELO := 0
const MURO := 1
const UMBRAL := 2


static func crear(tile_size: int, semilla: int = 0) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED
	ts.tile_size = Vector2i(tile_size, tile_size)

	var src := TileSetAtlasSource.new()
	src.texture = crear_textura(tile_size, semilla)
	src.texture_region_size = Vector2i(tile_size, tile_size)
	for y in range(FILAS):
		for x in range(COLUMNAS):
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	return ts


## Devuelve el atlas como textura. `semilla` fija el patrón para que el mismo
## mapa se vea igual aunque se regenere.
static func crear_textura(tile_size: int, semilla: int = 0) -> ImageTexture:
	var img := Image.create_empty(COLUMNAS * tile_size, FILAS * tile_size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("dtl_tiles:%d:%d" % [tile_size, semilla])

	var suelo := Color(0.27, 0.29, 0.36)
	var muro := Color(0.44, 0.46, 0.56)
	var umbral := Color(0.55, 0.45, 0.32)

	for y in range(FILAS):
		for x in range(COLUMNAS):
			var base: Color = [suelo, muro, umbral][y]
			_pintar_tesela(img, Vector2i(x * tile_size, y * tile_size), tile_size, base, rng, y == MURO)
	return ImageTexture.create_from_image(img)


static func _pintar_tesela(
	img: Image, origen: Vector2i, tile_size: int, base: Color, rng: RandomNumberGenerator, con_volumen: bool
) -> void:
	var grano := 0.055
	for y in range(tile_size):
		for x in range(tile_size):
			var c := base
			# Ruido suave: dos octavas de manchas + grano fino por píxel.
			var manchas := sin(x * 0.55 + y * 0.31) * cos(y * 0.47 - x * 0.19)
			var fino := rng.randf_range(-grano, grano)
			var variacion := clampf(manchas * grano * 0.8 + fino, -0.12, 0.12)
			c = Color(
				clampf(base.r + variacion, 0.0, 1.0),
				clampf(base.g + variacion, 0.0, 1.0),
				clampf(base.b + variacion, 0.0, 1.0),
				1.0
			)
			# Junta entre teselas del muro: simula ladrillo.
			if con_volumen and (x < 2 or y < 2 or x >= tile_size - 2 or y >= tile_size - 2):
				c = c.darkened(0.45)
			elif con_volumen and x < tile_size / 2 and (x + y * tile_size) % (tile_size / 2) < 1:
				c = c.darkened(0.18)
			img.set_pixel(origen.x + x, origen.y + y, c)


## Índice de tesela dentro del atlas. `fila` es SUELO, MURO o UMBRAL.
static func indice_para(fila: int, variante: int) -> Vector2i:
	return Vector2i(posmod(variante, COLUMNAS), fila)
