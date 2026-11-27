# Guardado de la partida (issue #52)

Lua no tiene `io`: el motor expone `save_data(slot, tabla)`, `load_data(slot)` y `has_save(slot)`
(ver [lua-api.md](../../../engine/docs/lua-api.md), seccion *Saving*). Quebrada usa una sola
ranura, `slot1`.

- Archivos: `~/Library/Application Support/Quebrada/save_slot1.json` (macOS; la carpeta de datos
  del usuario en otros sistemas), mas `save_slot1.json.bak` con el guardado anterior.
- Escritura atomica: se escribe un `.tmp` completo y se renombra encima. Si el proceso muere a
  mitad, el guardado anterior sigue valido; si el principal estuviera roto, se usa el `.bak`.

## Que se guarda

| Campo | Contenido |
| --- | --- |
| `version` | Version del formato (`save_logic.VERSION`) |
| `flags` | `world_state.snapshot()`: misiones y resultados, historias oidas, pistas y leyendas, casas y zonas desbloqueadas, dia, flags de dialogo... |
| `time.phase` | Fase del dia (`day`, `dusk`, `night`, `dawn`) |
| `foco.battery` | Bateria del foco (el foco se reanuda apagado) |
| `place` | `map`, `scene` y `ctx` (llegada pendiente, `return_*`, zona) para reaparecer en el mismo sitio |

No se guardan los sonidos en curso, la tarjeta de titulo ni la posicion exacta: se reaparece en
el spawn con el que se entro al mapa (o en el `default` si se guardo en pleno mapa). Los ajustes
de audio los guarda el motor aparte (`settings.json`). Las herramientas (#53) aun no existen: cuando
las haya, sus flags ya entran en `flags`.

## Cuando se guarda (autosave)

- Al entrar o salir de una casa (`town_controller.finish_other_map`, justo antes de `load_scene`).
- Al terminar una mision (`missions.complete` / `missions.fail`, despues de su hook).
- Al amanecer (`time_of_day.on_day`): dormir o pasar la noche.

`save.save()` guarda a mano; `save.autosave()` hace lo mismo sin lanzar nunca errores. Un fallo
solo escribe `[save] ...` en la consola.

## Continuar

En la escena principal, la tecla **7** llama a `save.load()` y abre la escena guardada. Restaura los
flags, la fase del dia, la bateria y el contexto de llegada antes de `load_scene`. Si no hay partida
(o es ilegible, de una version mas nueva o sin migracion) escribe el motivo en la consola.
Las teclas 5 y 6 abren los demos sin tocar el estado.

## Cambiar el formato (migraciones)

1. Sube `save_logic.VERSION` (de 1 a 2).
2. Agrega `save_logic.MIGRATIONS[1] = function(d) ... return d end`: convierte un guardado v1 en
   uno v2 (modifica `d` y devuelvelo; `migrate` sube `version` y encadena las migraciones).
3. Prueba la cadena en `tests/save_logic.lua`.

Un guardado de una version **mas nueva** que el juego se rechaza sin tocarlo.

## Notas

- Solo se guardan flags booleanos, numericos y de texto (lo que `snapshot()` ya filtra).
- Para borrar la partida, elimina `save_slot1.json` y `save_slot1.json.bak` de la carpeta de datos.
- Pruebas: `make test` (`engine/tests/SaveFileTest.cpp` para el disco, `tests/save_logic.lua` para la
  logica).
