#pragma once

#include <SDL2/SDL.h>
#include <string>
#include <vector>

// Un comando de imagen a dibujar en el frame actual (coordenadas de pantalla).
// front = false -> capa "back": debajo de las entidades
// front = true  -> capa "front": encima de las entidades y debajo del HUD
struct SpriteCommand {
  std::string assetId;
  int x;
  int y;
  int w;
  int h;
  Uint8 alpha;
  bool front;
  // Rect fuente opcional (px de la textura) y giro en grados (horario, como SDL)
  bool hasSrc = false;
  SDL_Rect src = { 0, 0, 0, 0 };
  double angle = 0.0;
};

// Buffer de modo inmediato: los scripts de Lua lo llenan durante update()
// y Game::render() lo consume y lo vacía despues de dibujar.
class SpriteBuffer {
  private:
    std::vector<SpriteCommand> commands;

  public:
    void push(const std::string& assetId, int x, int y, int w, int h, Uint8 alpha, bool front) {
        this->commands.push_back({ assetId, x, y, w, h, alpha, front, false, { 0, 0, 0, 0 }, 0.0 });
    }

    void push(const std::string& assetId, int x, int y, int w, int h, Uint8 alpha, bool front,
      bool hasSrc, const SDL_Rect& src, double angle) {
        this->commands.push_back({ assetId, x, y, w, h, alpha, front, hasSrc, src, angle });
    }

    void clear() { this->commands.clear(); }

    const std::vector<SpriteCommand>& getCommands() const { return this->commands; }
};
