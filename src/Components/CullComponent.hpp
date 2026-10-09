#pragma once

// Marca (sin datos) a las entidades que se "duermen" cuando quedan fuera del
// area activa (ver Util/Culling.hpp): no se simulan ni se dibujan. Se usa en
// las rocas de los chunks del mapa, que solo importan cerca del jugador.
struct CullComponent {
  CullComponent() = default;
};
