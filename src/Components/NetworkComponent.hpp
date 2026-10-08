#pragma once

#include <string>
#include <utility>

// Identidad de red de una entidad que existe en varias maquinas.
// netId tiene el formato "<playerId>:<contador>" (ej. "k3f9:12") y es lo unico
// que viaja por la red: los ids locales de Entity se reciclan y se reinician
// al cambiar de escena, asi que NUNCA deben enviarse.
// ownerId es el jugador que simula la entidad.
// Debe ser default-constructible porque Pool<T> redimensiona un std::vector<T>.
struct NetworkComponent {
  std::string netId;
  std::string ownerId;

  NetworkComponent(std::string netId = "", std::string ownerId = "")
    : netId(std::move(netId)), ownerId(std::move(ownerId)) {}
};
