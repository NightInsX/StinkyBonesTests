# Diagramas UML

Fuente en [Mermaid](https://mermaid.js.org/): GitHub la renderiza solo al ver el
fichero, y si no se puede usar [mermaid.live](https://mermaid.live) o la extensión
de VS Code con un previsualizador de Mermaid.

- [Diagrama de clases](#diagrama-de-clases)
- [Árbol de escena](#árbol-de-escena)
- [Onda: recorte, marcado y alerta](#onda-recorte-marcado-y-alerta)
- [Estados del enemigo](#estados-del-enemigo)

## Diagrama de clases

Sólo la API pública y el estado que importa; lo privado se agrupa en el diagrama
de secuencia o se omite. `Personaje` y `Pasillo` no llevan `class_name`, se
nombran aquí por lo que son.

```mermaid
classDiagram
    direction TB

    class DTLMapa {
        <<Node2D>>
        +signal generar_terminada(dimensiones)
        +tile : int
        +semilla : int
        +proporcion_sensibles : float
        +color_sensible : Color
        +colision_muros : bool
        +generar(nueva_semilla : bool)
        +punto_inicial() Vector2
        +es_transitable(celda) bool
        +es_muro(celda) bool
        +dimensiones() Vector2i
        +centro_celda(celda) Vector2
        +celda_de(punto) Vector2i
        +bloques() Array
        +bloques_sensibles() Array
        +bloque_en(punto) Bloque
        +es_navegable(punto) bool
        +celda_sala_cerca(desde, radio, minimo) Vector2i
        +probar_navegacion(desde, hasta) bool
    }

    class Bloque {
        <<StaticBody2D>>
        +signal impactado(duracion)
        +CAPA_MURO : int
        +CAPA_PERSONAJE : int
        +sensible : bool
        +chocado : bool
        +duracion_chocado : float
        +color_muro : Color
        +color_chocado : Color
        +color_chocado_sensible : Color
        +chocar()
        +tiempo_restante() float
        -_restante : float
    }

    class Echo {
        <<Node2D>>
        +AREA_GROUP : String
        +FUENTE_GROUP : String
        +CAPA_ONDA_JUGADORA : int
        +CAPA_ONDA_ENEMIGA : int
        +max_radius : float
        +duration : float
        +angulo : float
        +capa : int
        +capas_muro : int
        +tramos : int
        +muestras : int
        +recortada : bool
        +bloques_tocados : Array
        +ha_tocado_muros() bool
        +radio_actual() float
        +radio_maximo_alcanzado() float
        +radio_en_direccion(angulo_local) float
        +radios() PackedFloat32Array
        +alcanza(punto) bool
        +alcanza_local(lx, ly) bool
        +refrescar_recorte()
        -_wave_area : Area2D
        -_distancias : PackedFloat32Array
        -_recortar()
    }

    class SenalesTiles {
        <<Node2D>>
        +signal celda_marcada(celda)
        +signal mapa_revelado
        +capas_onda : int
        +nodo_mapa : NodePath
        +senal_de(celda) bool
        +celdas_con_senal() Array
        +quedan_por_revelar() int
        +revelado() bool
        +reiniciar()
        -_marcar_cono(onda)
        -_marcar_celda(celda)
        -_bandas : PackedByteArray
    }

    class Personaje {
        <<CharacterBody2D, sin class_name>>
        +SPEED : float
        +wave_max_radius : float
        +wave_duration : float
        +wave_cooldown : float
        +ralentizacion_segundos : float
        +factor_ralentizacion : float
        +alerta_enfriamiento : float
        +margen_alerta : float
        +encender_al_chocar : bool
        +tiene_llave : bool
        +emitir_onda()
        -_ralentizada : float
        -_chocar_con_sensibles()
        -_alertar_enemigo(punto)
    }

    class Enemigo {
        <<CharacterBody2D>>
        +GRUPO : StringName
        +velocidad_max : float
        +memoria_segundos : float
        +alerta_segundos : float
        +onda_max_radius : float
        +onda_intervalo : float
        +distancia_carga : float
        +alertar(punto)
        -_memoria : float
        -_alerta : bool
        -_oír_ondas()
        -_llega_el_sonido(onda) bool
        -_destino_libre(siguiente) Vector2
        -_aparecer(destino)
    }

    class Pasillo {
        <<Area2D, sin class_name>>
        +umbral : float
        +detectado : bool
        +detectar_onda(onda) bool
    }

    class Llave {
        <<Area2D>>
        +signal recogida(posicion)
        +celda : Vector2i
        +esta_recogida() bool
        +reponer()
    }

    class Puerta {
        <<Area2D>>
        +signal victoria(celda)
        +signal abierta(celda)
        +signal rechazada(celda)
        +celda : Vector2i
        +esta_abierta() bool
        +reponer()
    }

    class Objetivo {
        <<Node>>
        +colocar()
    }

    class MapaColocacion {
        <<Node>>
        +mapa : NodePath
        +nodos : Array
        +celda_preferida : Vector2i
    }

    class DTLTileSet {
        <<RefCounted, dtl_tileset.gd>>
        +SUELO : int
        +MURO : int
        +UMBRAL : int
    }

    DTLMapa "1" *-- "0..*" Bloque : crea los muros en _construir_colision
    DTLMapa --> DTLTileSet : pinta con
    Personaje ..> Echo : instancia echo.tscn y la lanza
    Enemigo ..> Echo : lanza ondas de sondeo
    Echo ..> Bloque : rayos del recorte, luego Bloque.chocar()
    SenalesTiles ..> Echo : recorre el grupo eco_fuente
    SenalesTiles --> DTLMapa : nodo_mapa, consulta de celdas
    Personaje ..> Enemigo : alertar() por el grupo enemigo
    Enemigo --> DTLMapa : navegación y celdas
    Pasillo ..> Echo : detectar_onda()
    Objetivo --> DTLMapa : elige suelo para salida y llave
    Objetivo --> Puerta
    Objetivo --> Llave
    Llave --> Personaje : escribe tiene_llave
    Puerta --> Personaje : comprueba tiene_llave
    MapaColocacion --> DTLMapa : reparte nodos por celdas
```

### Notas de las relaciones

| Relación | Por dónde va |
| --- | --- |
| `DTLMapa` → `Bloque` | `_construir_colision()` crea un `Bloque` por rectángulo de muro; `bloques()`, `bloques_sensibles()` y `bloque_en()` son la consulta pública. |
| `Echo` → `Bloque` | `_recortar()` lanza los rayos contra `Bloque.CAPA_MURO`, guarda los tocados en `bloques_tocados` y les llama `chocar()`. |
| `Personaje` → `Enemigo` | `_alertar_enemigo()` no guarda referencia: recorre el grupo `Enemigo.GRUPO` y llama `alertar(punto)`. |
| `SenalesTiles` → `Echo` | No hay referencia directa: `_process` recorre el grupo `Echo.FUENTE_GROUP` y le pregunta con `alcanza_local()`. |
| Señales sin consumidor | `celda_marcada`, `mapa_revelado`, `impactado`, `recogida`, `victoria`, `abierta` y `rechazada` están declaradas pero ninguna las conecta en la escena actual; sí se consumen `generar_terminada` (`Objetivo`, `SenalesTiles`) y `area_entered` de los `Oido`. |

## Árbol de escena

`scenes/main.tscn`, con los scripts que lleva cada nodo:

```mermaid
flowchart TB
    Root["main (Node2D)"]
    Root --> Mapa["MapaDTL : DTLMapa"]
    Root --> Senales["SenalesTiles : SenalesTiles"]
    Root --> Colocar["ColocarEnMapa : MapaColocacion"]
    Root --> Llave["Llave : Llave"]
    Root --> Puerta["Puerta : Puerta"]
    Root --> ObjetivoN["Objetivo : Objetivo"]
    Root --> Girl["girl : Personaje (CharacterBody2D)"]
    Root --> Enemy["Enemigo : Enemigo (CharacterBody2D)"]
    Root --> Nav["NavigationRegion2D"]

    Girl --> GirlSprite["Sprite2D"]
    Girl --> GirlShape["CollisionShape2D"]
    Girl --> GirlOido["Oido : Area2D"]
    Girl --> GirlCam["Camara : Camera2D"]

    Enemy --> EnemySprite["Sprite2D"]
    Enemy --> EnemyShape["CollisionShape2D"]
    Enemy --> Agente["Agente : NavigationAgent2D"]
    Enemy --> EnemyOido["Oido : Area2D"]

    Mapa -. genera .-> Bloques["Bloque 0..n (StaticBody2D)"]
    Girl -. instancia .-> Onda["Echo (Node2D)"]
    Enemy -. instancia .-> Onda
    Onda -. crea en código .-> Wave["WaveArea (Area2D)"]
    Onda -. rayos .-> Bloques
    Wave -. grupo echo_onda .-> OidoEnemigo["Oido del enemigo"]
```

Capas de colisión (una por script, para que el filtrado lo haga la física):

| Bit | Capa | Quién la usa |
| --- | --- | --- |
| 0 | `Bloque.CAPA_PERSONAJE` | `girl`, `Enemigo` |
| 1 | `Echo.CAPA_ONDA_JUGADORA` | ondas de la Girl, las oye el `Oido` del enemigo |
| 2 | `Echo.CAPA_ONDA_ENEMIGA` | ondas del enemigo, las oye el `Oido` de la Girl |
| 3 | `Bloque.CAPA_MURO` | muros; máscara de los rayos de `Echo` |

En `main.tscn` los `Oido` tienen la máscara a 0: cada script se la pone en
`_ready` (`character_body_2d.gd` con `CAPA_ONDA_ENEMIGA`, `enemigo.gd` con
`CAPA_ONDA_JUGADORA`), así que el filtrado vive en el código y no en la escena.

## Onda: recorte, marcado y alerta

El ciclo completo de una onda de la Girl, con el momento exacto en que cada cosa
se calcula (el recorte es una sola vez, el marcado es cada frame):

```mermaid
sequenceDiagram
    autonumber
    actor P as Personaje
    participant E as Echo
    participant B as Bloque
    participant S as SenalesTiles
    participant N as Enemigo

    P->>E: emitir_onda() instancía echo.tscn
    Note over E: forma de colisión: el cono entero,<br/>montada una vez en _build_wave_area()

    rect rgb(240, 248, 255)
    Note over E,B: primer tick de física, una sola vez<br/>(a menos que alguien llame a refrescar_recorte())
    E->>B: rayos del recorte: tramos x muestras (20x5 = 100)<br/>contra CAPA_MURO
    B-->>E: distancia al primer muro y collider
    E->>B: chocar() por cada bloque distinto tocado
    B-->>B: _restante = duracion_chocado, set_process(true)
    end

    loop cada frame (idle)
        S->>E: alcanza_local(lx, ly)
        Note over S: sólo las filas que el cono cruza<br/>(_marcar_cono estrecha el rango de dx)
        E-->>S: ¿dentro del cono y del recorte?
        S->>S: _marcar_celda() y signal celda_marcada
    end

    Note over P,B: cada frame, aunque la Girl vaya a velocidad 0:<br/>_chocar_con_sensibles() mira get_slide_collision()
    B-->>P: colisión de deslizamiento contra un bloque sensible
    P->>P: _ralentizada = ralentizacion_segundos<br/>(baja la marcha a factor_ralentizacion)
    P->>B: chocar() si encender_al_chocar
    P->>N: alertar(punto) si _alerta_enfriamiento <= 0
    Note over N: _alerta = true durante alerta_segundos,<br/>y mientras dura no se gasta _memoria

    loop mientras la onda viva
        N->>N: Oido.area_entered mete la onda en _ondas_oido
        N->>E: alcanza(posición del enemigo)
        N->>N: _llega_el_sonido() con 3 rayos de línea de visión
        E-->>N: llega de verdad
        N->>N: _memoria = memoria_segundos y _alerta = false<br/>(la onda manda sobre un golpe anterior)
    end
```

## Estados del enemigo

```mermaid
stateDiagram-v2
    direction LR

    [*] --> Paseo

    Paseo --> Paseo : llega a _destino<br/>sortea meta nueva y hace una pausa
    Paseo --> Carga : _oír_ondas() con línea de visión
    Paseo --> Alerta : alertar() golpe en bloque sensible

    Carga --> Alerta : alertar() mientras cargaba
    Carga --> Barrido : llega al punto oído<br/>barre radio_busqueda alrededor
    Barrido --> Barrido : punto barrido alcanzado, sortea otro
    Barrido --> Paseo : se le pasa la memoria
    Carga --> Paseo : se le pasa la memoria

    Alerta --> Paseo : pasan alerta_segundos<br/>(borra también la memoria)
    Alerta --> Carga : oye una onda mientras alerta<br/>(la onda manda)

    Paseo --> Aparicion : _caceria cruza intervalo_caceria
    Carga --> Aparicion : ídem
    Aparicion --> Carga : teletransporte cerca de la Girl<br/>_memoria = memoria_segundos, _alerta = false
```

`_moverse()` decide en este orden:

1. **`_cargando()`** — `true` si hay alerta (esa va siempre, sin comprobar
   distancia) o si `_memoria > 0` y el punto oído está a menos de
   `distancia_carga`. Va a `_ultima_onda_pos`; al llegar (`<= llegada`) entra en
   **Barrido** en vez de quedarse clavado.
2. **`_pausa`** — se para entre destinos.
3. **Paseo** — si ya está en `_destino`, sortea otra meta; si no, `_ir_a()`
   con `_destino_libre()` encima.

El **desatasque** no es un estado aparte: vive dentro de `_ir_a()`. Si
`_sin_avance` crece, sube `_nivel_atasco` y en cada escalón hace una cosa —
`_rodear_muro()` (elige lado del muro, `_borde_t`), `_retroceder()` (`_fuga_t`,
va para atrás sin ruta) y `_esquivar()` (punto cercano; si no hay ninguno se
rinde: borra memoria y alerta y sortea meta nueva).

La alerta tiene reloj propio (`_gastar_memoria()`): mientras dura, la memoria de
la onda no se gasta, porque el sonido se atenúa con la distancia y el golpe no.
