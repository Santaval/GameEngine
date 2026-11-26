#pragma once

#include <SDL2/SDL.h>
#include <string>

// Pasada en la que se dibuja el sprite respecto al tile map: Ground tras el suelo,
// World ordenado por Y con los tiles altos, Above tras las capas "above"
enum class SpriteLayer { Ground = 0, World = 1, Above = 2 };

// "ground" / "world" / "above" -> capa. false (y out intacto) si el nombre no existe
inline bool parseSpriteLayer(const std::string& name, SpriteLayer& out) {
    if (name == "ground") { out = SpriteLayer::Ground; return true; }
    if (name == "world") { out = SpriteLayer::World; return true; }
    if (name == "above") { out = SpriteLayer::Above; return true; }
    return false;
}

struct SpriteComponent {
    std::string teaxtureId;
    int width;
    int height;
    SDL_Rect srcRect;
    SpriteLayer layer = SpriteLayer::World;
    // Y de los "pies" para ordenar: -1 = borde inferior del frame actual; si no,
    // px desde el borde superior del frame (se multiplica por la escala)
    int sortOffset = -1;
    bool flipH = false;

    SpriteComponent(const std::string& textuteId = "none", int width = 0, int height = 0,
        int srcRecX = 0, int srcRectY = 0) {
            this->teaxtureId = textuteId;
            this->width = width;
            this->height = height;
            this->srcRect = {srcRecX, srcRectY, width, height};
    }
    
};
