#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>
#include <memory>
#include <set>
#include <string>
#include <sol/sol.hpp>

#include "../ECS/Registry.hpp"
#include "../AssetManager/AssetManager.hpp"
#include "../EventManager/EventManager.hpp"
#include "../ControllerManager/ControllerManager.hpp"
#include "../SceneManager/SceneLoader.hpp"
#include "../Util/TextBuffer.hpp"
#include "../Util/RectBuffer.hpp"

class NetClient;
class NetworkRegistry;
class NetworkScripting;
class DamageSync;

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
        RectBuffer rectBuffer;

        int milisecsPreviousFrame = 0;
        double deltaTime = 0.0;
        bool isRunning = false;
        bool showColliders = false;

        std::unique_ptr<AssetManager> assetManager;
        std::unique_ptr<EventManager> eventManager;
        std::unique_ptr<Registry> registry;
        sol::state lua;

        std::unique_ptr<SceneLoader> sceneLoader;

        // Multijugador: vacio = modo offline (no se conecta nada)
        std::unique_ptr<NetClient> netClient;
        // Identidad de red de las entidades (netId <-> Entity)
        std::unique_ptr<NetworkRegistry> networkRegistry;
        // Puente Lua <-> red. Declarado despues de lua: guarda funciones de Lua y
        // tiene que destruirse antes que el estado
        std::unique_ptr<NetworkScripting> networkScripting;
        // Daño/muerte con autoridad del dueño. Sus callbacks usan networkScripting
        // y netClient, asi que se destruye antes que ellos (declarado despues)
        std::unique_ptr<DamageSync> damageSync;
        std::string serverUrl;

        // Escena pedida desde Lua (load_scene); se carga al inicio del
        // proximo frame, nunca en medio de ScriptSystem::update
        std::string pendingScene;

        // Modulos de package.loaded que existen antes de cargar cualquier
        // escena (librerias de Lua). Todo lo demas se descarga al cambiar de
        // escena para que los require vuelvan a ejecutarse desde cero.
        std::set<std::string> builtinModules;

    public:
        std::unique_ptr<ControllerManager> controllerManager;



    
    private: 
        Game();
        ~Game();
        void processInput();
        void render();
        void update();
        void setup();
        void loadScene(const std::string& scenePath);
    
    public:
    static Game& getInstance();
     void init();
     void run();
     void destroy();
     void requestScene(const std::string& scenePath) { pendingScene = scenePath; }
     void setServerUrl(const std::string& url) { serverUrl = url; }
     NetClient* getNetClient() const { return netClient.get(); }
     NetworkRegistry* getNetworkRegistry() const { return networkRegistry.get(); }
     NetworkScripting* getNetworkScripting() const { return networkScripting.get(); }
     DamageSync* getDamageSync() const { return damageSync.get(); }
     SceneLoader* getSceneLoader() const { return sceneLoader.get(); }
     void quit() { isRunning = false; }
     double getDeltaTime() const { return deltaTime; }
     Registry* getRegistry() const { return registry.get(); }
     sol::state& getLua() { return lua; }
     SDL_Rect& getCamera() { return camera; }
     TextBuffer& getTextBuffer() { return textBuffer; }
     RectBuffer& getRectBuffer() { return rectBuffer; }
     int getWindowWidth() const { return windowWidth; }
     int getWindowHeight() const { return windowHeight; }
     bool isShowingColliders() const { return showColliders; }
     void setShowColliders(bool value) { showColliders = value; }
     void toggleShowColliders() { showColliders = !showColliders; }
};