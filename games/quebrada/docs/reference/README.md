# Referencia del pueblo real (issue #54)

Material para dibujar el mapa y los tiles de Quebrada Grande. Son referencias, no assets del juego.

## Croquis

`croquis.svg`: redibujado a partir del croquis del documento de conceptualización. Norte arriba.

- **Camino de las carretas**: calle vertical al este; baja desde las eólicas hasta la casa de mamá.
- **Calle horizontal**: cruza el pueblo y termina en el camino.
- **Calle 2**: vertical, a mitad del mapa, cruza la calle horizontal. En el mapa ya está: es la "calle oeste" (adoquín junto al parque, sigue de lastre al sur) que pasa frente al Ebais (confirmado por el usuario).
- **Río**: la quebrada recorre todo el NORTE del pueblo, irregular (a ~175 m de la iglesia, ~20 m del cafetal, ~50 m de la casa de mamá). Ya está en el mapa (docs/rio.md); el cruce de la calle de asfalto es un puente de concreto con barandas amarillas oxidadas.
- **Este del camino**: Eólicas (arriba), Iglesia (en medio).
- **Entre calle 2 y el camino**: Escuela (norte de la calle horizontal), Parque (sur).
- **Oeste de calle 2**: Ebais (la clínica).
- **Extremo oeste**: Níspero y hule (sur de la calle horizontal) y el Cafetal enfrente, del otro lado de la calle.
- **Colegio**: en el mapa está al sur de la calle principal, frente al cafetal (docs/school.md). Casa de mamá sigue al oeste del camino.

Cambios respecto al croquis original: se agregó el cafetal (el documento lo pide al frente del monte).
Pendiente: contar los pasos iglesia → casa para fijar la escala.

## Fotos

| Lugar | Archivos | Notas |
|---|---|---|
| Aerogeneradores | `aerogeneradores/*` (4) | torre con vehículo para escala, camino a la cresta, atardecer con laguna, vista aérea (ya usadas: el aerogenerador de `tilesets/monte.png`, ver `docs/monte.md`) |
| Camino de las carretas | `camino/camino-de-carretas.jpg` | lastre y piedra, huellas, franjas de zacate |
| Monte de hule y níspero | `monte/*` (3) | ladera boscosa, potrero y palma al frente; vista aérea del bosque con laguna de cráter (útil para la copa de los árboles; ya usadas: los hules y nísperos de `tilesets/monte.png`, ver `docs/monte.md`) |
| Río | `rio/quebrada-piedras.jpg` | |
| Cafetal | `cafetal/cafetal-terrazas.jpg` | filas en terrazas |
| Clínica (Ebais) | `clinica/ebais-rampa.jpg` | piedra arriba, techo de zinc azul, rampa con barandas amarillas, calle de adoquín |
| Escuela | `escuela/escuela-frente.jpg` | techo de zinc rojo, columnas rosadas, malla ciclón, bancas de madera |
| Iglesia | `iglesia/iglesia-frente.jpg` | blanca, aguja roja, puertas café, setos |

Se dejaron fuera por tener marca de agua o de Google Street View: una torre con logo (TOROSI), la vista aérea del bosque con logos de televisión (`huleynis3`), el paso del río con logo, calle de lastre, calle de asfalto (Ruta Nacional Terciaria, doble línea amarilla), la casa de mamá (paredes blancas, techo de zinc claro con borde rojo, ventana arqueada con cortinas, moto tapada con lona, árbol grande al frente) y el colegio (Liceo, paredes verde claro, cerca baja y rotulo en el muro).

## Faltan para cerrar el issue

- Por lo menos 3 fotos por lugar de la zona 1 (hoy hay 1–4; faltan Parque, Colegio y Casa propias).
- Fotos nocturnas del camino con los postes de luz.
- Conteo de pasos iglesia → casa.
