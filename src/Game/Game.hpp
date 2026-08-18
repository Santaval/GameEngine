#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>

class Game {
    private:
        SDL_Window* window = nullptr;
        SDL_Renderer* renderer = nullptr;

        int windowWidth = 0;
        int windowHeight = 0;

        bool isRunning = false;

    
    private: 
        void processInput();
        void render();
        void update();
    
    public:
     Game();
     ~Game();

     void init();
     void run();
     void destroy();
};