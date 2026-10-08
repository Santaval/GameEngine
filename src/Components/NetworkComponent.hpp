#pragma once

#include <string>
#include <utility>
#include <nlohmann/json.hpp>

// Identidad de red de una entidad que existe en varias maquinas.
// netId tiene el formato "<playerId>:<contador>" (ej. "k3f9:12") y es lo unico
// que viaja por la red: los ids locales de Entity se reciclan y se reinician
// al cambiar de escena, asi que NUNCA deben enviarse.
// ownerId es el jugador que simula la entidad.
// Debe ser default-constructible porque Pool<T> redimensiona un std::vector<T>.
struct NetworkComponent {
  std::string netId;
  std::string ownerId;
  // false: el dueno no manda "state" (balas: todos las simulan desde "fire")
  bool syncState;
  // Prefab con el que se anuncio ("" si no tiene: balas); sirve para describirla en un snapshot
  std::string script;
  // Estado con el que se anuncio (extras de Lua: kind, scale, ring...)
  nlohmann::json spawnState;
  // Entidad del mundo (asteroide, loot...): la simula el host y migra con el
  bool world = false;

  NetworkComponent(std::string netId = "", std::string ownerId = "", bool syncState = true)
    : netId(std::move(netId)), ownerId(std::move(ownerId)), syncState(syncState) {}
};
