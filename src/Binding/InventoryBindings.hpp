#pragma once

#include <sol/sol.hpp>

#include <algorithm>
#include <string>
#include <tuple>

#include "../ECS/Entity.hpp"
#include "../Components/InventoryComponent.hpp"

// Mismo criterio que EquipmentBindings: getComponent no valida nada, asi que
// los getters devuelven un valor neutro cuando falta el componente o el item
// en vez de leer basura

// -1 si no esta
inline int findInventoryIndex(const InventoryList& items, const std::string& name) {
  for (std::size_t i = 0; i < items.size(); i++) {
    if (items[i].first == name) return static_cast<int>(i);
  }
  return -1;
}

inline int inventoryTotal(const InventoryList& items) {
  int total = 0;
  for (const auto& item : items) total += item.second;
  return total;
}

inline bool hasInventory(Entity e) {
  return e.hasComponent<InventoryComponent>();
}

inline int getInventoryTotal(Entity e) {
  if (!e.hasComponent<InventoryComponent>()) return 0;
  return inventoryTotal(e.getComponent<InventoryComponent>().items);
}

inline int getInventoryCapacity(Entity e) {
  if (!e.hasComponent<InventoryComponent>()) return 0;
  return e.getComponent<InventoryComponent>().capacity;
}

// 0 = sin limite. Bajar la capacidad por debajo del total actual no tira
// items, queda documentado asi (ver docs/inventory.md).
inline void setInventoryCapacity(Entity e, int capacity) {
  if (!e.hasComponent<InventoryComponent>()) {
    e.addComponent<InventoryComponent>(InventoryList{}, capacity);
    return;
  }

  e.getComponent<InventoryComponent>().capacity = capacity;
}

inline int getItemCount(Entity e, const std::string& name) {
  if (!e.hasComponent<InventoryComponent>()) return 0;

  const auto& items = e.getComponent<InventoryComponent>().items;
  int index = findInventoryIndex(items, name);
  if (index == -1) return 0;

  return items[index].second;
}

inline bool hasItem(Entity e, const std::string& name, sol::optional<int> qty) {
  return getItemCount(e, name) >= qty.value_or(1);
}

// Suma qty (default 1) respetando el cupo si lo hay, y devuelve cuanto se
// agrego de verdad. Crea el componente (sin limite) si faltaba. Solo agrega
// una entrada nueva si algo se pudo meter.
inline int addItem(Entity e, const std::string& name, sol::optional<int> qty) {
  int amount = qty.value_or(1);
  if (amount <= 0) return 0;

  if (!e.hasComponent<InventoryComponent>()) {
    e.addComponent<InventoryComponent>(InventoryList{});
  }

  auto& inventory = e.getComponent<InventoryComponent>();
  if (inventory.capacity > 0) {
    int free = inventory.capacity - inventoryTotal(inventory.items);
    amount = std::min(amount, free);
  }
  if (amount <= 0) return 0;

  int index = findInventoryIndex(inventory.items, name);
  if (index == -1) {
    inventory.items.emplace_back(name, amount);
  } else {
    inventory.items[index].second += amount;
  }

  return amount;
}

// Quita qty (default 1), nunca mas de lo que hay, y devuelve cuanto se quito
// de verdad. Borra la entrada si llega a 0.
inline int removeItem(Entity e, const std::string& name, sol::optional<int> qty) {
  int amount = qty.value_or(1);
  if (amount <= 0) return 0;
  if (!e.hasComponent<InventoryComponent>()) return 0;

  auto& items = e.getComponent<InventoryComponent>().items;
  int index = findInventoryIndex(items, name);
  if (index == -1) return 0;

  int removed = std::min(amount, items[index].second);
  items[index].second -= removed;
  if (items[index].second <= 0) items.erase(items.begin() + index);

  return removed;
}

// Fija la cantidad absoluta (no suma/resta). Crea el componente (sin limite)
// si faltaba. count <= 0 borra la entrada. Con capacidad > 0 se recorta para
// que el total nunca supere el cupo, sin tocar lo que ya tenian los demas
// items. Devuelve la cantidad que quedo realmente.
inline int updateItemCount(Entity e, const std::string& name, int count) {
  if (count <= 0) {
    // nada que crear solo para borrar una entrada que ni existe
    if (!e.hasComponent<InventoryComponent>()) return 0;

    auto& items = e.getComponent<InventoryComponent>().items;
    int index = findInventoryIndex(items, name);
    if (index != -1) items.erase(items.begin() + index);
    return 0;
  }

  if (!e.hasComponent<InventoryComponent>()) {
    e.addComponent<InventoryComponent>(InventoryList{});
  }

  auto& inventory = e.getComponent<InventoryComponent>();
  auto& items = inventory.items;
  int index = findInventoryIndex(items, name);
  int held = index == -1 ? 0 : items[index].second;

  int finalCount = count;
  if (inventory.capacity > 0) {
    // total del resto de items (sin contar lo que este ya tenia)
    int otherTotal = inventoryTotal(items) - held;
    int maxAllowed = inventory.capacity - otherTotal;
    if (maxAllowed < 0) maxAllowed = 0;
    if (finalCount > maxAllowed) finalCount = maxAllowed;
  }

  if (finalCount <= 0) {
    if (index != -1) items.erase(items.begin() + index);
    return 0;
  }

  if (index == -1) {
    items.emplace_back(name, finalCount);
  } else {
    items[index].second = finalCount;
  }

  return finalCount;
}

inline int getInventoryCount(Entity e) {
  if (!e.hasComponent<InventoryComponent>()) return 0;
  return static_cast<int>(e.getComponent<InventoryComponent>().items.size());
}

// 1-based, igual que get_equipment_at. Fuera de rango devuelve "", 0 en vez
// de crashear.
inline std::tuple<std::string, int> getInventoryAt(Entity e, int index) {
  if (!e.hasComponent<InventoryComponent>()) return { std::string(""), 0 };

  const auto& items = e.getComponent<InventoryComponent>().items;
  int i = index - 1;
  if (i < 0 || i >= static_cast<int>(items.size())) return { std::string(""), 0 };

  return { items[i].first, items[i].second };
}

inline void clearInventory(Entity e) {
  if (!e.hasComponent<InventoryComponent>()) return;
  e.getComponent<InventoryComponent>().items.clear();
}

inline void registerInventoryBindings(sol::state& lua) {
  lua.set_function("has_inventory", hasInventory);
  lua.set_function("add_item", addItem);
  lua.set_function("remove_item", removeItem);
  lua.set_function("update_item_count", updateItemCount);
  lua.set_function("get_item_count", getItemCount);
  lua.set_function("has_item", hasItem);
  lua.set_function("get_inventory_total", getInventoryTotal);
  lua.set_function("get_inventory_capacity", getInventoryCapacity);
  lua.set_function("set_inventory_capacity", setInventoryCapacity);
  lua.set_function("get_inventory_count", getInventoryCount);
  lua.set_function("get_inventory_at", getInventoryAt);
  lua.set_function("clear_inventory", clearInventory);
}
