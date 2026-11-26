#pragma once

#include <string>
#include <utility>
#include <vector>

// Coleccion nombre -> nivel para las herramientas mejorables del jugador
// (engine, gun, shield, ...). Solo tracking: ningun sistema todavia lee
// estos niveles, eso queda para cuando se cablee el gameplay.
//
// Vector de pares y no unordered_map, por tres razones de este motor:
// 1. Pool<T> reserva 1000 instancias de entrada (ver Pool.hpp), y un vector
//    vacio no aloca nada; un unordered_map vacio ya pesa mas y cada entrada
//    mete un nodo en el heap.
// 2. Pool::set copia el componente por valor en cada addComponent, asi que
//    cada copia extra del contenedor (el nodo del map) sale cara.
// 3. El HUD necesita recorrer las herramientas siempre en el mismo orden;
//    un hash no lo garantiza. Con 3-10 herramientas la busqueda lineal le
//    gana igual al hash.
using EquipmentList = std::vector<std::pair<std::string, int>>;

struct EquipmentComponent
{
  EquipmentList equipment;  // nombre -> nivel, en orden de insercion

  // removeComponent solo apaga el bit de la firma y nunca limpia el Pool
  // (ver Registry.hpp/Registry.cpp), y los ids de entidad se reciclan; por
  // eso el constructor siempre reescribe la lista entera y nunca la deja
  // como estaba, para que una entidad reciclada no herede el equipo de la
  // anterior.
  EquipmentComponent(EquipmentList equipment = {}) {
    this->equipment = equipment;
  }
};
