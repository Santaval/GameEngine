# Apagón de la noche del chequelo

Con la misión en `night_active` (`mission.chequelo.night_active`):
- `time_of_day.blackout()` apaga con fundido (2,5 s) **todas** las luces del mapa (casas y postes) y `roofs.lua` apaga las ventanas. Al amanecer vuelven. Quedan solo el foco, la luz compañera (#81) y el halo del jugador.
- `scripts/blackout.lua` (cfg.on_tick de zona1): sonido del corte al empezar, bucle de viento con silbido, silbidos lejanos al azar y caballos (relinchos existentes + resoplidos y trote nuevos) a 180-340 px del jugador.

## Audios (los de `sounds/` son silencios provisionales: reemplazar con el mismo nombre)
| Archivo | Uso |
|---|---|
| `sounds/sfx/sfx_power_cut.mp3` | corte de la luz al empezar la noche |
| `sounds/amb/amb_blackout_loop.mp3` | bucle de fondo (debe cerrar sin corte) |
| `sounds/sfx/sfx_whistle_01..03.mp3` | silbidos lejanos |
| `sounds/sfx/sfx_horse_snort_01..02.mp3` | resoplidos |
| `sounds/sfx/sfx_horse_hooves_far_01.mp3` | trote lejano |
