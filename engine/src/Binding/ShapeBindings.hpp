#pragma once

#include <SDL2/SDL.h>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

namespace {
  inline SDL_Color makeRectColor(sol::optional<int> r, sol::optional<int> g,
    sol::optional<int> b, sol::optional<int> a) {
      return {
        static_cast<Uint8>(r.value_or(255)), static_cast<Uint8>(g.value_or(255)),
        static_cast<Uint8>(b.value_or(255)), static_cast<Uint8>(a.value_or(255))
      };
  }
}

// HUD: la posición es en pantalla, no se mueve con la cámara
inline void drawRect(float x, float y, float w, float h,
  sol::optional<int> r, sol::optional<int> g, sol::optional<int> b, sol::optional<int> a,
  sol::optional<bool> filled) {
    Game::getInstance().getRectBuffer().push(static_cast<int>(x), static_cast<int>(y),
      static_cast<int>(w), static_cast<int>(h), makeRectColor(r, g, b, a),
      filled.value_or(true), false);
}

// La posición es del mundo: sigue a la cámara
inline void drawRectWorld(float x, float y, float w, float h,
  sol::optional<int> r, sol::optional<int> g, sol::optional<int> b, sol::optional<int> a,
  sol::optional<bool> filled) {
    Game::getInstance().getRectBuffer().push(static_cast<int>(x), static_cast<int>(y),
      static_cast<int>(w), static_cast<int>(h), makeRectColor(r, g, b, a),
      filled.value_or(true), true);
}

inline void registerShapeBindings(sol::state& lua) {
  lua.set_function("draw_rect", drawRect);
  lua.set_function("draw_rect_world", drawRectWorld);
}
