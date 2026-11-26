#pragma once

#include <SDL2/SDL.h>
#include <string>


struct SpriteComponent {
    std::string teaxtureId;
    int width;
    int height;
    SDL_Rect srcRect;

    SpriteComponent(const std::string& textuteId = "none", int width = 0, int height = 0,
        int srcRecX = 0, int srcRectY = 0) {
            this->teaxtureId = textuteId;
            this->width = width;
            this->height = height;
            this->srcRect = {srcRecX, srcRectY, width, height};
    }
    
};