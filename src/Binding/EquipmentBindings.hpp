#pragma once

#include <sol/sol.hpp>

#include <string>
#include <tuple>

#include "../ECS/Entity.hpp"
#include "../Components/EquipmentComponent.hpp"

// getComponent no valida nada (ver Registry), asi que los getters devuelven
// un valor neutro cuando falta el componente o la herramienta en vez de leer
// basura

// -1 si no esta
inline int findEquipmentIndex(const EquipmentList& equipment, const std::string& name) {
  for (std::size_t i = 0; i < equipment.size(); i++) {
    if (equipment[i].first == name) return static_cast<int>(i);
  }
  return -1;
}

inline void setEquipmentLevel(Entity e, const std::string& name, int level) {
  if (!e.hasComponent<EquipmentComponent>()) {
    e.addComponent<EquipmentComponent>(EquipmentList{});
  }

  auto& equipment = e.getComponent<EquipmentComponent>().equipment;
  int index = findEquipmentIndex(equipment, name);

  if (index == -1) {
    equipment.emplace_back(name, level);
  } else {
    equipment[index].second = level;
  }
}

inline int getEquipmentLevel(Entity e, const std::string& name) {
  if (!e.hasComponent<EquipmentComponent>()) return 0;

  const auto& equipment = e.getComponent<EquipmentComponent>().equipment;
  int index = findEquipmentIndex(equipment, name);
  if (index == -1) return 0;

  return equipment[index].second;
}

inline bool hasEquipment(Entity e, const std::string& name) {
  if (!e.hasComponent<EquipmentComponent>()) return false;

  const auto& equipment = e.getComponent<EquipmentComponent>().equipment;
  return findEquipmentIndex(equipment, name) != -1;
}

// Sube "amount" (default 1) y devuelve el nivel nuevo. Si la herramienta no
// estaba, la crea directamente en el nivel "amount" (patron set_damage).
inline int upgradeEquipment(Entity e, const std::string& name, sol::optional<int> amount) {
  int delta = amount.value_or(1);
  int newLevel = getEquipmentLevel(e, name) + delta;
  setEquipmentLevel(e, name, newLevel);
  return newLevel;
}

inline void removeEquipment(Entity e, const std::string& name) {
  if (!e.hasComponent<EquipmentComponent>()) return;

  auto& equipment = e.getComponent<EquipmentComponent>().equipment;
  int index = findEquipmentIndex(equipment, name);
  if (index == -1) return;

  equipment.erase(equipment.begin() + index);
}

inline int getEquipmentCount(Entity e) {
  if (!e.hasComponent<EquipmentComponent>()) return 0;
  return static_cast<int>(e.getComponent<EquipmentComponent>().equipment.size());
}

// 1-based: para que "for i = 1, get_equipment_count(this)" se lea como Lua
// normal. Fuera de rango devuelve "", 0 en vez de crashear.
inline std::tuple<std::string, int> getEquipmentAt(Entity e, int index) {
  if (!e.hasComponent<EquipmentComponent>()) return { std::string(""), 0 };

  const auto& equipment = e.getComponent<EquipmentComponent>().equipment;
  int i = index - 1;
  if (i < 0 || i >= static_cast<int>(equipment.size())) return { std::string(""), 0 };

  return { equipment[i].first, equipment[i].second };
}

inline void registerEquipmentBindings(sol::state& lua) {
  lua.set_function("set_equipment_level", setEquipmentLevel);
  lua.set_function("get_equipment_level", getEquipmentLevel);
  lua.set_function("has_equipment", hasEquipment);
  lua.set_function("upgrade_equipment", upgradeEquipment);
  lua.set_function("remove_equipment", removeEquipment);
  lua.set_function("get_equipment_count", getEquipmentCount);
  lua.set_function("get_equipment_at", getEquipmentAt);
}
