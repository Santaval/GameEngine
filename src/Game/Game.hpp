#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>
#include <memory>

#include "../ECS/Registry.hpp"

class Game {
    private:
        SDL_Window* window = nullptr;
        SDL_Renderer* renderer = nullptr;

        int windowWidth = 0;
        int windowHeight = 0;

        std::unique_ptr<Registry> registry;

        bool isRunning = false;

    
    private: 
        Game();
        ~Game();
        void processInput();
        void render();
        void update();
        void setup();
    
    public:
    static Game& getInstance();
     void init();
     void run();
     void destroy();
};