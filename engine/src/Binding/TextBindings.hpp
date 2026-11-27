#pragma once

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <sol/sol.hpp>
#include <algorithm>
#include <string>
#include <tuple>

#include "../Game/Game.hpp"
#include "../AssetManager/AssetManager.hpp"
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

// HUD con ajuste de línea: maxW en unidades lógicas, el texto se parte por palabras
inline void drawTextWrapped(float x, float y, float maxW, const std::string& text,
  sol::optional<std::string> fontId,
  sol::optional<int> r, sol::optional<int> g, sol::optional<int> b, sol::optional<int> a) {
    Game::getInstance().getTextBuffer().push(text, fontId.value_or("default"),
      static_cast<int>(x), static_cast<int>(y), makeTextColor(r, g, b, a), false,
      static_cast<int>(maxW));
}

// Tamaño del texto en unidades lógicas (px nativos / escala, redondeado arriba).
// Con maxW > 0 mide el texto ajustado a ese ancho.
inline std::tuple<int, int> measureText(const std::string& text,
  sol::optional<std::string> fontId, sol::optional<int> maxW) {
    AssetManager* assets = Game::getInstance().getAssetManager();
    if (!assets || text.empty()) return std::make_tuple(0, 0);
    TTF_Font* font = assets->getFont(fontId.value_or("default"));
    if (!font) return std::make_tuple(0, 0);
    const int scale = std::max(1, Game::getInstance().getLayout().scale);
    int w = 0, h = 0;
    if (maxW && *maxW > 0) {
      SDL_Color white = { 255, 255, 255, 255 };
      SDL_Surface* s = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), white,
        static_cast<Uint32>(*maxW * scale));
      if (!s) return std::make_tuple(0, 0);
      w = s->w; h = s->h;
      SDL_FreeSurface(s);
    } else if (TTF_SizeUTF8(font, text.c_str(), &w, &h) != 0) {
      return std::make_tuple(0, 0);
    }
    return std::make_tuple((w + scale - 1) / scale, (h + scale - 1) / scale);
}

// Alto de línea de la fuente en unidades lógicas
inline int getLineHeight(sol::optional<std::string> fontId) {
    AssetManager* assets = Game::getInstance().getAssetManager();
    if (!assets) return 0;
    TTF_Font* font = assets->getFont(fontId.value_or("default"));
    if (!font) return 0;
    const int scale = std::max(1, Game::getInstance().getLayout().scale);
    return (TTF_FontLineSkip(font) + scale - 1) / scale;
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
  lua.set_function("draw_text_wrapped", drawTextWrapped);
  lua.set_function("measure_text", measureText);
  lua.set_function("get_line_height", getLineHeight);
  lua.set_function("add_text", addText);
  lua.set_function("set_text", setText);
  lua.set_function("set_text_color", setTextColor);
}
