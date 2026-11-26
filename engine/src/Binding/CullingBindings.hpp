#pragma once

#include <sol/sol.hpp>

#include "../Util/Culling.hpp"

// Area activa del mundo: las entidades con CullComponent fuera de ella se
// duermen (no se simulan ni se dibujan). Ver Util/Culling.hpp.
inline void setActiveArea(double minX, double minY, double maxX, double maxY) {
  ActiveArea& area = activeArea();
  area.minX = minX;
  area.minY = minY;
  area.maxX = maxX;
  area.maxY = maxY;
  area.enabled = true;
}

inline void clearActiveArea() {
  activeArea().enabled = false;
}

inline void registerCullingBindings(sol::state& lua) {
  lua.set_function("set_active_area", setActiveArea);
  lua.set_function("clear_active_area", clearActiveArea);
}
