#pragma once

#include <algorithm>
#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

// Coordenadas de pantalla. layer: "back" (bajo las entidades) o "front" (por defecto,
// sobre las entidades y bajo el HUD). a por defecto 255.
// opts = { src = {x, y, w, h}, angle = grados }: rect fuente y giro horario alrededor del centro
inline void drawImage(const std::string& assetId, float x, float y, float w, float h,
  sol::optional<int> a, sol::optional<std::string> layer, sol::optional<sol::table> opts) {
    int alpha = std::clamp(a.value_or(255), 0, 255);
    bool front = layer.value_or("front") != "back";
    bool hasSrc = false;
    SDL_Rect src = { 0, 0, 0, 0 };
    double angle = 0.0;
    if (opts) {
        sol::optional<sol::table> srcTable = (*opts)["src"];
        if (srcTable) {
            src.x = static_cast<int>(srcTable->get_or("x", 0.0));
            src.y = static_cast<int>(srcTable->get_or("y", 0.0));
            src.w = static_cast<int>(srcTable->get_or("w", 0.0));
            src.h = static_cast<int>(srcTable->get_or("h", 0.0));
            hasSrc = true;
        }
        angle = opts->get_or("angle", 0.0);
    }
    Game::getInstance().getSpriteBuffer().push(assetId, static_cast<int>(x), static_cast<int>(y),
      static_cast<int>(w), static_cast<int>(h), static_cast<Uint8>(alpha), front, hasSrc, src, angle);
}

inline void registerImageBindings(sol::state& lua) {
  lua.set_function("draw_image", drawImage);
}
