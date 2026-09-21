#pragma once

#include <SDL2/SDL.h>
#include <sol/sol.hpp>
#include <string>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/TextComponent.hpp"

namespace {
  inline SDL_Color makeTextColor(sol::optional<int> r, sol::optional<int> g,
    sol::optional<int> b, sol::optional<int> a) {
      return {
        static_cast<Uint8>(r.value_or(255)), static_cast<Uint8>(g.value_or(255)),
        static_cast<Uint8>(b.value_or(255)), static_cast<Uint8>(a.value_or(255))
      };
  }
}

// HUD: la posición es en pantalla, no se mueve con la cámara
inline void drawText(float x, float y, const std::string& text,
  sol::optional<std::string> fontId,
  sol::optional<int> r, sol::optional<int> g, sol::optional<int> b, sol::optional<int> a) {
    Game::getInstance().getTextBuffer().push(text, fontId.value_or("default"),
      static_cast<int>(x), static_cast<int>(y), makeTextColor(r, g, b, a), false);
}

// La posición es del mundo: sigue a la cámara
inline void drawTextWorld(float x, float y, const std::string& text,
  sol::optional<std::string> fontId,
  sol::optional<int> r, sol::optional<int> g, sol::optional<int> b, sol::optional<int> a) {
    Game::getInstance().getTextBuffer().push(text, fontId.value_or("default"),
      static_cast<int>(x), static_cast<int>(y), makeTextColor(r, g, b, a), true);
}

// Etiqueta persistente pegada a una entidad (usa su TransformComponent)
inline void addText(Entity e, const std::string& text, sol::optional<std::string> fontId,
  sol::optional<int> r, sol::optional<int> g, sol::optional<int> b, sol::optional<int> a,
  sol::optional<int> offsetX, sol::optional<int> offsetY) {
    e.addComponent<TextComponent>(text, fontId.value_or("default"),
      r.value_or(255), g.value_or(255), b.value_or(255), a.value_or(255),
      true, offsetX.value_or(0), offsetY.value_or(0));
}

inline void setText(Entity e, const std::string& text) {
  auto& textComponent = e.getComponent<TextComponent>();
  textComponent.text = text;
}

inline void setTextColor(Entity e, int r, int g, int b, sol::optional<int> a) {
  auto& textComponent = e.getComponent<TextComponent>();
  textComponent.color = makeTextColor(r, g, b, a);
}

inline void registerTextBindings(sol::state& lua) {
  lua.set_function("draw_text", drawText);
  lua.set_function("draw_text_world", drawTextWorld);
  lua.set_function("add_text", addText);
  lua.set_function("set_text", setText);
  lua.set_function("set_text_color", setTextColor);
}
