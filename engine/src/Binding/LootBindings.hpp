#pragma once

#include <sol/sol.hpp>

#include <string>
#include <tuple>

#include "../ECS/Entity.hpp"
#include "../Components/LootComponent.hpp"

// Mismo criterio que InventoryBindings: los getters devuelven un valor neutro
// cuando falta el componente en vez de leer basura

inline bool hasLoot(Entity e) {
  return e.hasComponent<LootComponent>();
}

inline int getLootCount(Entity e) {
  if (!e.hasComponent<LootComponent>()) return 0;
  return static_cast<int>(e.getComponent<LootComponent>().items.size());
}

// 1-based, igual que get_inventory_at. Fuera de rango devuelve "", 0
inline std::tuple<std::string, int> getLootAt(Entity e, int index) {
  if (!e.hasComponent<LootComponent>()) return { std::string(""), 0 };

  const auto& items = e.getComponent<LootComponent>().items;
  int i = index - 1;
  if (i < 0 || i >= static_cast<int>(items.size())) return { std::string(""), 0 };

  return { items[i].first, items[i].second };
}

// Fija la cantidad absoluta de un item (no suma). Crea el componente si
// faltaba, que es como se marcan los pickups creados desde Lua. qty <= 0
// borra la entrada.
inline void setLoot(Entity e, const std::string& name, int qty) {
  if (!e.hasComponent<LootComponent>()) {
    if (qty <= 0) return;
    e.addComponent<LootComponent>(LootList{});
  }

  auto& items = e.getComponent<LootComponent>().items;
  for (std::size_t i = 0; i < items.size(); i++) {
    if (items[i].first != name) continue;

    if (qty <= 0) {
      items.erase(items.begin() + i);
    } else {
      items[i].second = qty;
    }
    return;
  }

  if (qty > 0) items.emplace_back(name, qty);
}

inline void registerLootBindings(sol::state& lua) {
  lua.set_function("has_loot", hasLoot);
  lua.set_function("get_loot_count", getLootCount);
  lua.set_function("get_loot_at", getLootAt);
  lua.set_function("set_loot", setLoot);
}
