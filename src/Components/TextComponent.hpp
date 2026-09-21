#pragma once

#include <SDL2/SDL.h>
#include <string>

// Etiqueta de texto pegada a una entidad: se dibuja en la posición de su
// TransformComponent más el offset. Nunca guarda punteros a texturas: el
// caché vive en el TextRenderSystem (los componentes no se destruyen nunca).
struct TextComponent
{
  std::string text;
  std::string fontId;
  SDL_Color color;
  bool isWorldSpace;
  int offsetX;
  int offsetY;

  TextComponent(const std::string& text = "", const std::string& fontId = "default",
    int r = 255, int g = 255, int b = 255, int a = 255,
    bool isWorldSpace = true, int offsetX = 0, int offsetY = 0) {
      this->text = text;
      this->fontId = fontId;
      this->color = {
        static_cast<Uint8>(r), static_cast<Uint8>(g),
        static_cast<Uint8>(b), static_cast<Uint8>(a)
      };
      this->isWorldSpace = isWorldSpace;
      this->offsetX = offsetX;
      this->offsetY = offsetY;
  }
};
