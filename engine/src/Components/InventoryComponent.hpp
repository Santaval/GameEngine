#pragma once

#include <string>
#include <utility>
#include <vector>

// Coleccion nombre -> cantidad para los objetos que una entidad recolecta
// (mineral, chatarra, ...) mas un tope de capacidad opcional. Mismo patron
// que EquipmentComponent: solo almacenamiento, ningun sistema lee esto por
// su cuenta, todo pasa por los bindings de Lua.
//
// Vector de pares y no unordered_map, por las mismas tres razones que
// EquipmentComponent (ver ese archivo): el Pool<T> reserva 1000 entradas
// vacias, Pool::set copia el componente entero por valor, y el HUD necesita
// un orden estable que un hash no garantiza.
using InventoryList = std::vector<std::pair<std::string, int>>;

struct InventoryComponent
{
  InventoryList items;   // nombre -> cantidad, en orden de insercion; nunca
                          // hay entradas con cantidad 0 (se borran al llegar ahi)
  int capacity;           // tope de unidades totales sumando todos los items;
                           // 0 = sin limite

  // removeComponent solo apaga el bit de la firma y nunca limpia el Pool
  // (ver Registry.hpp/Registry.cpp), y los ids de entidad se reciclan; por
  // eso el constructor siempre reescribe items y capacity por completo y
  // nunca los deja como estaban, para que una entidad reciclada no herede
  // el inventario de la anterior.
  InventoryComponent(InventoryList items = {}, int capacity = 0) {
    this->items = items;
    this->capacity = capacity;
  }
};
