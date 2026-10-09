#include "Game.hpp"

#include <iostream>

#include "../Network/NetClient.hpp"
#include "../Network/DamageSync.hpp"
#include "../Network/WorldSync.hpp"
#include "../Network/NetworkRegistry.hpp"
#include "../Network/NetworkScripting.hpp"
#include "../Util/Culling.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/ScriptComponent.hpp"
#include "../Components/TextComponent.hpp"
#include "../Components/PathComponent.hpp"

#include "../Systems/CollisionSystem.hpp"
#include "../Systems/RenderSystem.hpp"
#include "../Systems/MovementSystem.hpp"
#include "../Systems/GravitySystem.hpp"
#include "../Systems/DamageSystem.hpp"
#include "../Systems/AnimationSystem.hpp"
#include "../Systems/ScriptSystem.hpp"
#include "../Systems/NetSyncSystem.hpp"
#include "../Systems/TextRenderSystem.hpp"
#include "../Systems/PathRenderSystem.hpp"
#include "../Systems/ColliderRenderSystem.hpp"

Game::Game() {
    this->assetManager = std::make_unique<AssetManager>();
    this->eventManager = std::make_unique<EventManager>();
    this->controllerManager = std::make_unique<ControllerManager>();
    this->registry = std::make_unique<Registry>(); 
    this->networkRegistry = std::make_unique<NetworkRegistry>(this->registry.get());
    this->netClient = std::make_unique<NetClient>();

    this->sceneLoader = std::make_unique<SceneLoader>(); 
    std::cout << "[Game] Game init" << std::endl;
}

Game::~Game() {
    this->networkScripting.reset();
    this->netClient.reset();
    this->networkRegistry.reset();
    this->assetManager.reset();
    this->controllerManager.reset();
    this->eventManager.reset();
    this->registry.reset();
    std::cout << "[Game] Game destroy" << std::endl;
}

void Game::init() {
    if (SDL_Init(SDL_INIT_EVERYTHING) != 0) {
        std::cout << "[Game] Error initializing SDL" << std::endl;
        return;
    }

    if (TTF_Init() != 0) {
        std::cout << "[Game] Error initializing SDL TTF" << std::endl;
        return;
    }

    SDL_DisplayMode displayMode;
    SDL_GetCurrentDisplayMode(0, &displayMode);

    this->windowWidth = displayMode.w;
    this->windowHeight = displayMode.h;

    this->camera = { 0, 0, this->windowWidth, this->windowHeight };

    window = SDL_CreateWindow(
        "Engine",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        this->windowWidth,
        this->windowHeight,
        SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN_DESKTOP
    );

    if (!this->window) {
        std::cout << "[Game] Error creating window" << std::endl;
        return;
    }
    
    renderer = SDL_CreateRenderer(this->window,-1,0);

    if (!this->renderer) {
        std::cout << "[Game] Error creating renderer" << std::endl;
        return;
    }

    this->isRunning = true;
}

void Game::setup() {
    this->registry->addSystem<RenderSystem>();
    this->registry->addSystem<MovementSystem>();
    this->registry->addSystem<GravitySystem>();
    this->registry->addSystem<CollisionSystem>();
    this->registry->addSystem<DamageSystem>();
    this->registry->addSystem<AnimationSystem>();
    this->registry->addSystem<ScriptSystem>();
    this->registry->addSystem<NetSyncSystem>();
    this->registry->addSystem<TextRenderSystem>();
    this->registry->addSystem<PathRenderSystem>();
    this->registry->addSystem<ColliderRenderSystem>();

    this->lua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string, sol::lib::package);
    this->lua["package"]["path"] = "./assets/scripts/?.lua;./assets/scripts/player/?.lua;" +
        this->lua["package"]["path"].get<std::string>();
    this->registry->getSystem<ScriptSystem>().createLuaBiding(this->lua);
    this->networkScripting = std::make_unique<NetworkScripting>(*this->netClient,
        *this->networkRegistry, *this->registry, this->lua, *this->sceneLoader);

    // Correccion de deriva: los "state" de los duenos llegan por poll()
    this->netClient->subscribe("state", [this](const nlohmann::json& msg) {
        this->registry->getSystem<NetSyncSystem>().onState(msg, *this->networkRegistry);
    });

    // Daño y muerte: solo el dueño de cada entidad decide su vida
    this->damageSync = std::make_unique<DamageSync>(*this->networkRegistry,
        [this](const nlohmann::json& msg) { this->netClient->send(msg); },
        [this]() { return this->netClient->isOnline(); },
        [](Entity e, int amount) {
            // Solo visual: el resultado del hook no puede tocar la vida
            callScriptHook(e, &ScriptComponent::onDamage, amount, sol::optional<Entity>(sol::nullopt));
        },
        [](Entity e) { killWithHooks(e); },
        [this](const std::string& netId) {
            auto entity = this->networkRegistry->find(netId);
            if (entity) {
                this->networkScripting->despawn(*entity);
            } else {
                // Ya murio aqui: las demas maquinas aun tienen su copia
                this->netClient->send({{"t", "despawn"}, {"netId", netId}});
            }
        });
    this->netClient->subscribe("damage", [this](const nlohmann::json& msg) {
        this->damageSync->onDamage(msg, SDL_GetTicks());
    });
    this->netClient->subscribe("death", [this](const nlohmann::json& msg) {
        this->damageSync->onDeath(msg);
    });
    this->netClient->subscribe("room_settings", [this](const nlohmann::json& msg) {
        // Solo el host manda los ajustes de la sala
        if (msg.value("from", std::string()) != this->netClient->getHostId()) return;
        this->damageSync->onRoomSettings(msg);
    });
    this->netClient->subscribe("snapshot", [this](const nlohmann::json& msg) {
        if (msg.value("from", std::string()) != this->netClient->getHostId()) return;
        this->damageSync->onSnapshot(msg);
    });
    // Reconexion: el servidor nos olvido y el resto tambien a nosotros
    this->netClient->subscribe("welcome", [this](const nlohmann::json& msg) {
        this->snapshotRequested = false;
        this->worldSync->onWelcome(msg.value("playerId", std::string()), msg.value("hostId", std::string()));
    });

    // Mundo del host: migracion, salida de jugadores y snapshot para recien llegados.
    // Va antes de cualquier net_on de Lua: la adopcion en C++ corre primero
    this->worldSync = std::make_unique<WorldSync>(*this->networkRegistry, *this->registry,
        [this](const nlohmann::json& msg) { this->netClient->send(msg); },
        [this]() { return this->netClient->isOnline(); });
    this->netClient->subscribe("peer_left", [this](const nlohmann::json& msg) {
        this->worldSync->onPeerLeft(msg.value("playerId", std::string()));
    });
    this->netClient->subscribe("host_changed", [this](const nlohmann::json& msg) {
        this->worldSync->onHostChanged(msg.value("hostId", std::string()));
    });
    this->netClient->subscribe("custom", [this](const nlohmann::json& msg) {
        this->worldSync->onCustom(msg);
    });
    this->netClient->subscribe("snapshot_request", [this](const nlohmann::json& msg) {
        this->worldSync->onSnapshotRequest(msg, this->damageSync->pvpEnabled(),
            this->damageSync->getMatchSeed());
    });

    sol::table loaded = this->lua["package"]["loaded"];
    for (const auto& entry : loaded) {
        this->builtinModules.insert(entry.first.as<std::string>());
    }

    this->loadScene("./assets/scripts/scenes/menu.lua");
}

// La conexion solo la inicia el menu (opcion Multiplayer), nunca el arranque
bool Game::connectToServer() {
    if (this->serverUrl.empty()) {
        return false;
    }
    std::cout << "[Net] connecting to " << this->serverUrl << std::endl;
    this->netClient->connect(this->serverUrl, "player");
    return true;
}

void Game::disconnectFromServer() {
    this->netClient->disconnect();
    this->damageSync->resetSettings();
    this->snapshotRequested = false;
}

void Game::loadScene(const std::string& scenePath) {
    std::cout << "[Game] Loading scene " << scenePath << std::endl;

    // Primero se sueltan las entidades: sus ScriptComponent guardan
    // funciones de los scripts que se van a volver a ejecutar
    // Reinicio (misma escena): el host avisa que su mundo se descarta; sin esto
    // los demas conservarian copias huerfanas. Si sale a otra escena (menu) se
    // desconecta y el mundo migra al siguiente host, asi que no se borra
    if (this->worldSync && scenePath == this->currentScene) this->worldSync->announceWorldReset();
    this->currentScene = scenePath;
    this->registry->clear();
    this->networkRegistry->clear();
    this->registry->getSystem<NetSyncSystem>().clear();
    // La escena nueva arranca sin las entidades de los demas: se vuelven a pedir
    this->snapshotRequested = false;
    // Los handlers de net_on pertenecen a la escena que se descarga
    if (this->networkScripting) {
        this->networkScripting->clearHandlers();
    }
    this->textBuffer.clear();
    this->rectBuffer.clear();
    this->camera.x = 0;
    this->camera.y = 0;
    // El area activa es de la escena que se descarga (set_active_area la vuelve a fijar)
    activeArea().enabled = false;

    // Los modulos cacheados por require guardan estado en sus locals
    // (cooldowns, menus abiertos...): se descargan para empezar limpio
    sol::table loaded = this->lua["package"]["loaded"];
    std::vector<std::string> toUnload;
    for (const auto& entry : loaded) {
        std::string name = entry.first.as<std::string>();
        if (this->builtinModules.count(name) == 0) {
            toUnload.push_back(name);
        }
    }
    for (const auto& name : toUnload) {
        loaded[name] = sol::lua_nil;
    }

    // Globals compartidos entre scripts que apuntarian a entidades viejas
    this->lua["player_entity"] = sol::lua_nil;
    this->lua["game_over"] = sol::lua_nil;

    this->sceneLoader->load(scenePath, this->lua, this->assetManager,
        this->controllerManager, this->registry, this->renderer);
}


void Game::processInput() {
    int mouseX, mouseY;
    SDL_GetMouseState(&mouseX, &mouseY);
    this->controllerManager->setMousePosition(mouseX, mouseY);

    SDL_Event sdlEvent;
    while(SDL_PollEvent(&sdlEvent)) {

        switch(sdlEvent.type) {

            case SDL_QUIT:
                this->isRunning = false;
                break;
            case SDL_KEYDOWN:
                if(sdlEvent.key.keysym.sym == SDLK_ESCAPE) {
                    this->isRunning = false;
                    break;
                }
                this->controllerManager->keyDown(sdlEvent.key.keysym.sym);
                break;
            case SDL_KEYUP:
                this->controllerManager->keyUp(sdlEvent.key.keysym.sym);
                break;
            case SDL_MOUSEBUTTONDOWN:
                this->controllerManager->mouseButtonDown(sdlEvent.button.button);
                break;
            case SDL_MOUSEBUTTONUP:
                this->controllerManager->mouseButtonUp(sdlEvent.button.button);
                break;
            default:
                break;
        }
    }
}

void Game::render() {
    // Casi negro: fondo de espacio
    SDL_SetRenderDrawColor(this->renderer, 10, 10, 18, 255);
    SDL_RenderClear(this->renderer);

    this->registry->getSystem<RenderSystem>().update(this->renderer, this->assetManager, this->camera);

    // La trayectoria va encima de los sprites pero debajo del HUD de texto
    this->registry->getSystem<PathRenderSystem>().update(this->renderer, this->camera, this->deltaTime);

    // Overlay de debug: se salta por completo cuando está apagado
    if (this->showColliders) {
        this->registry->getSystem<ColliderRenderSystem>().update(this->renderer, this->camera);
    }

    // Paneles del HUD (rectangulos): van antes del texto para que el texto quede encima
    SDL_SetRenderDrawBlendMode(this->renderer, SDL_BLENDMODE_BLEND);
    for (const auto& rect : this->rectBuffer.getCommands()) {
        SDL_Rect sdlRect = { rect.x, rect.y, rect.w, rect.h };
        if (rect.isWorldSpace) {
            sdlRect.x -= this->camera.x;
            sdlRect.y -= this->camera.y;
        }

        SDL_SetRenderDrawColor(this->renderer, rect.color.r, rect.color.g, rect.color.b, rect.color.a);
        if (rect.filled) {
            SDL_RenderFillRect(this->renderer, &sdlRect);
        } else {
            SDL_RenderDrawRect(this->renderer, &sdlRect);
        }
    }

    // El texto va después de los sprites para que quede encima
    this->registry->getSystem<TextRenderSystem>().update(this->renderer, this->assetManager,
        this->camera, this->textBuffer);

    // Los comandos duran un frame: los scripts los vuelven a pedir en el próximo update()
    this->textBuffer.clear();
    this->rectBuffer.clear();

    SDL_RenderPresent(this->renderer);
}

void Game::update() {
    int timeToWait = MILISECS_PER_FRAMES - (SDL_GetTicks() - this->milisecsPreviousFrame);

    if(timeToWait > 0 &&   MILISECS_PER_FRAMES >= timeToWait) {
        SDL_Delay(timeToWait);
    }

    double deltaTime = (SDL_GetTicks() - this->milisecsPreviousFrame) / 1000.0;
    this->deltaTime = deltaTime;

    this->milisecsPreviousFrame = SDL_GetTicks();

    // Red: los handlers corren aqui, en el hilo principal, antes de todo lo demas
    this->netClient->poll();
    this->networkRegistry->setLocalPlayerId(this->netClient->getMyPlayerId());

    // Lo que llego mientras estabamos en otra escena (el menu) se borro al
    // cargar esta: el host responde con un snapshot y cada jugador con su nave
    if (this->netClient->isOnline() && !this->snapshotRequested) {
        this->snapshotRequested = true;
        this->netClient->send({{"t", "snapshot_request"}});
    }

    // Reset events subscriptions
    this->eventManager->reset();
    this->registry->getSystem<DamageSystem>().subscribeToCollisionEvent(this->eventManager);
    this->registry->getSystem<ScriptSystem>().subscribeToCollisionEvent(this->eventManager);

    this->registry->update();
    this->registry->getSystem<ScriptSystem>().update(this->lua);
    // Replicacion de estado: envia lo propio y corrige lo ajeno antes de simular
    for (auto& msg : this->registry->getSystem<NetSyncSystem>().update(
            deltaTime, *this->networkRegistry, this->netClient->isOnline())) {
        this->netClient->send(std::move(msg));
    }
    this->registry->getSystem<AnimationSystem>().update();
    // La gravedad suma a la velocidad antes de integrar el movimiento
    this->registry->getSystem<GravitySystem>().update(deltaTime);
    this->registry->getSystem<MovementSystem>().update(deltaTime);
    this->registry->getSystem<CollisionSystem>().update(this->eventManager);
}


void Game::run() {
    this->setup();

    while(this->isRunning) {
        if (!this->pendingScene.empty()) {
            std::string scenePath = this->pendingScene;
            this->pendingScene.clear();
            this->loadScene(scenePath);
        }

        this->processInput();
        this->update();
        this->render();
    }
}

void Game::destroy() {
    this->netClient->disconnect();

    // Las texturas y las fuentes tienen que morir antes que el renderer y antes de TTF_Quit
    this->registry->getSystem<TextRenderSystem>().clearCache();
    this->assetManager->clearAll();

    SDL_DestroyRenderer(this->renderer);
    SDL_DestroyWindow(this->window);
    TTF_Quit();
    SDL_Quit();
}

Game& Game::getInstance() {
    static Game game;
    return game;
}