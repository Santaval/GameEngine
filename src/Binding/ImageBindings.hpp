#pragma once

#include <algorithm>
#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

// Coordenadas de pantalla. layer: "back" (bajo las entidades) o "front" (por defecto,
// sobre las entidades y bajo el HUD). a por defecto 255
inline void drawImage(const std::string& assetId, float x, float y, float w, float h,
  sol::optional<int> a, sol::optional<std::string> layer) {
    int alpha = std::clamp(a.value_or(255), 0, 255);
    bool front = layer.value_or("front") != "back";
    Game::getInstance().getSpriteBuffer().push(assetId, static_cast<int>(x), static_cast<int>(y),
      static_cast<int>(w), static_cast<int>(h), static_cast<Uint8>(alpha), front);
}

inline void registerImageBindings(sol::state& lua) {
  lua.set_function("draw_image", drawImage);
}
