#pragma once

#include <sol/sol.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/PathComponent.hpp"

// Agrega el componente si falta (por defecto activo, o el valor pedido)
inline void addPath(Entity e, sol::optional<bool> active) {
  e.addComponent<PathComponent>(active.value_or(true));
}

// getComponent no valida nada (Registry.hpp), así que si el componente no
// existe se agrega en vez de corromper memoria leyendo/escribiendo basura
inline void setPathActive(Entity e, bool active) {
  if (!e.hasComponent<PathComponent>()) {
    e.addComponent<PathComponent>(active);
    return;
  }

  auto& path = e.getComponent<PathComponent>();
  path.active = active;
}

inline bool isPathActive(Entity e) {
  if (!e.hasComponent<PathComponent>()) return false;
  return e.getComponent<PathComponent>().active;
}

inline void registerPathBindings(sol::state& lua) {
  lua.set_function("add_path", addPath);
  lua.set_function("set_path_active", setPathActive);
  lua.set_function("is_path_active", isPathActive);
}
