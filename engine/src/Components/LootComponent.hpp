#pragma once

#include <string>
#include <utility>
#include <vector>

// Lo que suelta una entidad (nombre -> cantidad). Un asteroide lo lee en
// on_death para saber que pickups generar, y cada pickup lo lleva para saber
// que le entrega a quien lo recoge. Mismo patron que InventoryComponent: solo
// almacenamiento, ningun sistema lo lee por su cuenta, todo pasa por Lua.
//
// No se reutiliza InventoryComponent a proposito: has_inventory(other) es lo
// que decide quien puede recoger, y si los pickups o los asteroides tuvieran
// inventario empezarian a "recogerse" entre ellos.
using LootList = std::vector<std::pair<std::string, int>>;

struct LootComponent
{
  LootList items;   // nombre -> cantidad; nunca hay entradas con cantidad 0

  // Mismo motivo que InventoryComponent: el Pool nunca se limpia y los ids se
  // reciclan, asi que el constructor siempre reescribe items por completo.
  LootComponent(LootList items = {}) {
    this->items = items;
  }
};
