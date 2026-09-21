#pragma once

#include <SDL2/SDL.h>
#include <string>
#include <vector>

// Un comando de texto a dibujar en el frame actual.
// isWorldSpace = true  -> la posición es del mundo y le resta la cámara
// isWorldSpace = false -> HUD, posición fija en pantalla
struct TextCommand {
  std::string text;
  std::string fontId;
  int x;
  int y;
  SDL_Color color;
  bool isWorldSpace;
};

// Buffer de modo inmediato: los scripts de Lua lo llenan durante update()
// y el TextRenderSystem lo consume y lo vacía en render().
class TextBuffer {
  private:
    std::vector<TextCommand> commands;

  public:
    void push(const std::string& text, const std::string& fontId, int x, int y,
      SDL_Color color, bool isWorldSpace) {
        this->commands.push_back({ text, fontId, x, y, color, isWorldSpace });
    }

    // clear() conserva la capacidad: no hay reservas por frame
    void clear() { this->commands.clear(); }

    const std::vector<TextCommand>& getCommands() const { return this->commands; }
};
