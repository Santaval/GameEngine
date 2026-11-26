#pragma once

#include <SDL2/SDL.h>
#include <vector>

// Un comando de rectangulo a dibujar en el frame actual.
// isWorldSpace = true  -> la posición es del mundo y le resta la cámara
// isWorldSpace = false -> HUD, posición fija en pantalla
struct RectCommand {
  int x;
  int y;
  int w;
  int h;
  SDL_Color color;
  bool filled;
  bool isWorldSpace;
};

// Buffer de modo inmediato: los scripts de Lua lo llenan durante update()
// y Game::render() lo consume y lo vacía despues de dibujar.
class RectBuffer {
  private:
    std::vector<RectCommand> commands;

  public:
    void push(int x, int y, int w, int h, SDL_Color color, bool filled, bool isWorldSpace) {
        this->commands.push_back({ x, y, w, h, color, filled, isWorldSpace });
    }

    // clear() conserva la capacidad: no hay reservas por frame
    void clear() { this->commands.clear(); }

    const std::vector<RectCommand>& getCommands() const { return this->commands; }
};
