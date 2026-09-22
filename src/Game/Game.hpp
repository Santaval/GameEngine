#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>
#include <memory>
#include <sol/sol.hpp>

#include "../ECS/Registry.hpp"
#include "../AssetManager/AssetManager.hpp"
#include "../EventManager/EventManager.hpp"
#include "../ControllerManager/ControllerManager.hpp"
#include "../SceneManager/SceneLoader.hpp"
#include "../Util/TextBuffer.hpp"

const int FPS = 30;
const int MILISECS_PER_FRAMES = 1000 / FPS;

class Game {
    private:
        SDL_Window* window = nullptr;
        SDL_Renderer* renderer = nullptr;

        int windowWidth = 0;
        int windowHeight = 0;

        SDL_Rect camera = {0, 0, 0, 0};

        // Se llena desde los scripts en update() y se vacía en render()
        TextBuffer textBuffer;

        int milisecsPreviousFrame = 0;
        double deltaTime = 0.0;
        bool isRunning = false;
        bool showColliders = false;

        std::unique_ptr<AssetManager> assetManager;
        std::unique_ptr<EventManager> eventManager;
        std::unique_ptr<Registry> registry;
        sol::state lua;

        std::unique_ptr<SceneLoader> sceneLoader;

    public:
        std::unique_ptr<ControllerManager> controllerManager;



    
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
     double getDeltaTime() const { return deltaTime; }
     Registry* getRegistry() const { return registry.get(); }
     SDL_Rect& getCamera() { return camera; }
     TextBuffer& getTextBuffer() { return textBuffer; }
     int getWindowWidth() const { return windowWidth; }
     int getWindowHeight() const { return windowHeight; }
     bool isShowingColliders() const { return showColliders; }
     void setShowColliders(bool value) { showColliders = value; }
     void toggleShowColliders() { showColliders = !showColliders; }
};