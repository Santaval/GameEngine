#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>
#include <memory>
#include <set>
#include <vector>
#include <string>
#include <sol/sol.hpp>

#include "../ECS/Registry.hpp"
#include "../AssetManager/AssetManager.hpp"
#include "../Audio/AudioManager.hpp"
#include "../EventManager/EventManager.hpp"
#include "../ControllerManager/ControllerManager.hpp"
#include "../SceneManager/SceneLoader.hpp"
#include "../Physics/StaticWorld.hpp"
#include "../Util/TextBuffer.hpp"
#include "../Util/RectBuffer.hpp"
#include "../Util/SpriteBuffer.hpp"
#include "../Util/PixelPerfect.hpp"

class NetClient;
class NetworkRegistry;
class NetworkScripting;
class DamageSync;
class WorldSync;
class TileMapRenderSystem;

const int FPS = 30;
const int MILISECS_PER_FRAMES = 1000 / FPS;

class Game {
    private:
        SDL_Window* window = nullptr;
        SDL_Renderer* renderer = nullptr;

        int windowWidth = 0;
        int windowHeight = 0;

        // Ventana nativa (pixeles reales de la pantalla o de game.lua width/height)
        int nativeWidth = 0;
        int nativeHeight = 0;
        // Modo pixel-perfect activo: logical_size + pixel_perfect = true
        bool pixelPerfect = false;
        // Resolucion logica (lo que ve Lua) cuando el modo esta activo
        int logicalWidth = 0;
        int logicalHeight = 0;
        // Escala entera y letterbox del area logica dentro de la salida
        pixelperfect::Layout layout;

        SDL_Rect camera = {0, 0, 0, 0};

        // Se llena desde los scripts en update() y se vacía en render()
        TextBuffer textBuffer;
        RectBuffer rectBuffer;
        SpriteBuffer spriteBuffer;

        int milisecsPreviousFrame = 0;
        double deltaTime = 0.0;
        bool isRunning = false;
        bool showColliders = false;

        std::unique_ptr<AssetManager> assetManager;
        // Declarado despues de assetManager: guarda una referencia a el
        std::unique_ptr<AudioManager> audioManager;
        std::unique_ptr<EventManager> eventManager;
        std::unique_ptr<Registry> registry;
        sol::state lua;

        // Paredes y tiles solidos del nivel (no son entidades). Se vacia al
        // cargar una escena; lo llenan los scripts (add_static_box, load_tmx_colliders)
        physics::StaticWorld staticWorld;

        // Tile map cargado con load_tile_map (no son entidades). Se descarta al
        // cambiar de escena. Solo se declara aqui: el tipo completo vive en
        // Systems/TileMapRenderSystem.hpp (Game.cpp y TileMapBindings.hpp)
        std::unique_ptr<TileMapRenderSystem> tileMap;
        // Ordenar por Y los sprites World y los tiles altos; se activa solo con
        // un mapa cargado o con set_y_sort(true)
        bool ySort = false;

        std::unique_ptr<SceneLoader> sceneLoader;

        // Entidad que oye el audio espacial (set_listener); -1 = automatico
        // (player_entity de Lua o, si no hay, el centro de la camara)
        int listenerEntity = -1;

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
        std::unique_ptr<WorldSync> worldSync;
        std::string serverUrl;
        // Pedido de entidades ya existentes ("snapshot_request") hecho para la
        // escena actual; se repite al cargar escena o al reconectar
        bool snapshotRequested = false;

        // Escena pedida desde Lua (load_scene); se carga al inicio del
        // proximo frame, nunca en medio de ScriptSystem::update
        std::string pendingScene;
        // Escena cargada: distingue un reinicio (misma escena) de salir de ella
        std::string currentScene;

        // Modulos de package.loaded que existen antes de cargar cualquier
        // escena (librerias de Lua). Todo lo demas se descarga al cambiar de
        // escena para que los require vuelvan a ejecutarse desde cero.
        std::set<std::string> builtinModules;

        // Juego elegido al arrancar (--game / GAME); por defecto "aval".
        // Su raiz es ./games/<nombre>/
        std::string gameName;
        std::string gameRoot = "./games/aval";
        // Opcional, de <raiz>/game.lua; 0 / vacio = valores por defecto
        std::string windowTitle = "Engine";
        int configWidth = 0;
        int configHeight = 0;
        // logical_size = { w=, h= } y pixel_perfect = bool (opcionales, ver docs)
        int configLogicalW = 0;
        int configLogicalH = 0;
        bool configPixelPerfect = false;

        void loadGameConfig();
        std::string buildPackagePath() const;
        std::string entryScenePath() const;

    public:
        std::unique_ptr<ControllerManager> controllerManager;



    
    private: 
        Game();
        ~Game();
        void processInput();
        void render();
        void drawSprites(int layer, const pixelperfect::Layout& view = pixelperfect::Layout());
        // Pasada del modo pixel-perfect: solo mundo, solo HUD, o todo (modo apagado)
        enum class RectPass { All, World, Hud };
        void drawRects(RectPass pass);
        void drawLetterbox();
        void updateLayout();
        void update();
        // Ultimo paso de update(): fija el oyente y mueve las voces espaciales
        void updateSpatialAudio(double dt);
        void setup();
        void loadScene(const std::string& requestedScene);
    
    public:
    static Game& getInstance();
     void init();
     void run();
     void destroy();
     void requestScene(const std::string& scenePath) { pendingScene = scenePath; }
     // Debe llamarse antes de init(). Devuelve false si el nombre es invalido
     // o games/<nombre>/ (con scenes/main.lua) no existe (el motivo se escribe en error).
     bool setGame(const std::string& name, std::string& error);
     const std::string& getGameName() const { return gameName; }
     const std::string& getGameRoot() const { return gameRoot; }
     void setServerUrl(const std::string& url) { serverUrl = url; }
     const std::string& getServerUrl() const { return serverUrl; }
     bool connectToServer();
     void disconnectFromServer();
     NetClient* getNetClient() const { return netClient.get(); }
     NetworkRegistry* getNetworkRegistry() const { return networkRegistry.get(); }
     NetworkScripting* getNetworkScripting() const { return networkScripting.get(); }
     DamageSync* getDamageSync() const { return damageSync.get(); }
     WorldSync* getWorldSync() const { return worldSync.get(); }
     SceneLoader* getSceneLoader() const { return sceneLoader.get(); }
     void quit() { isRunning = false; }
     double getDeltaTime() const { return deltaTime; }
     AudioManager* getAudio() const { return audioManager.get(); }
     void setListener(int entityId) { listenerEntity = entityId; }
     Registry* getRegistry() const { return registry.get(); }
     sol::state& getLua() { return lua; }
     physics::StaticWorld& getStaticWorld() { return staticWorld; }
     // Carga un .tmx para dibujarlo en (x, y) del mundo y reemplaza el anterior.
     // false con el motivo en error si falla (el mapa anterior se conserva)
     bool loadTileMap(const std::string& path, double x, double y, std::string& error);
     void unloadTileMap();
     TileMapRenderSystem* getTileMap() const { return tileMap.get(); }
     void setYSort(bool value) { ySort = value; }
     bool isYSort() const { return ySort; }
     SDL_Rect& getCamera() { return camera; }
     TextBuffer& getTextBuffer() { return textBuffer; }
     RectBuffer& getRectBuffer() { return rectBuffer; }
     SpriteBuffer& getSpriteBuffer() { return spriteBuffer; }
     int getWindowWidth() const { return windowWidth; }
     int getWindowHeight() const { return windowHeight; }
     bool isPixelPerfect() const { return pixelPerfect; }
     const pixelperfect::Layout& getLayout() const { return layout; }
     bool isShowingColliders() const { return showColliders; }
     void setShowColliders(bool value) { showColliders = value; }
     void toggleShowColliders() { showColliders = !showColliders; }
};