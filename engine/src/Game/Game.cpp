#include "Game.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <iostream>

#include "../Network/NetClient.hpp"
#include "../Network/DamageSync.hpp"
#include "../Network/WorldSync.hpp"
#include "../Network/NetworkRegistry.hpp"
#include "../Network/NetworkScripting.hpp"
#include "../Util/AudioBus.hpp"
#include "../Util/Culling.hpp"
#include "../Util/GamePath.hpp"
#include "../Util/Settings.hpp"
#include "../Map/TmxLoader.hpp"
#include "../Map/TileMap.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/BoxColliderComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/ScriptComponent.hpp"
#include "../Components/TextComponent.hpp"
#include "../Components/PathComponent.hpp"

#include "../Systems/BoxColliderSystem.hpp"
#include "../Systems/BoxColliderRenderSystem.hpp"
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
#include "../Systems/TileMapRenderSystem.hpp"
#include "../Systems/SpatialAudioSystem.hpp"
#include "../Systems/LightingSystem.hpp"

Game::Game() {
    this->assetManager = std::make_unique<AssetManager>();
    this->audioManager = std::make_unique<AudioManager>(*this->assetManager);
    this->eventManager = std::make_unique<EventManager>();
    this->controllerManager = std::make_unique<ControllerManager>();
    this->registry = std::make_unique<Registry>(); 
    this->networkRegistry = std::make_unique<NetworkRegistry>(this->registry.get());
    this->netClient = std::make_unique<NetClient>();

    this->sceneLoader = std::make_unique<SceneLoader>(); 
    std::cout << "[Game] Game init" << std::endl;
}

Game::~Game() {
    this->tileMap.reset();
    this->networkScripting.reset();
    this->netClient.reset();
    this->networkRegistry.reset();
    this->audioManager.reset();
    this->assetManager.reset();
    this->controllerManager.reset();
    this->eventManager.reset();
    this->registry.reset();
    std::cout << "[Game] Game destroy" << std::endl;
}

bool Game::setGame(const std::string& name, std::string& error) {
    const std::string game = name.empty() ? std::string(DEFAULT_GAME) : name;
    for (char c : game) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '-') {
            error = "invalid game name '" + game + "' (use letters, digits, '_' or '-')";
            return false;
        }
    }
    const std::string root = std::string(GAMES_DIR) + "/" + game;
    if (!std::filesystem::is_directory(root)) {
        error = "game '" + game + "' not found: " + root + " does not exist (run from the repo root)";
        return false;
    }
    if (!std::filesystem::is_regular_file(root + "/scenes/main.lua")) {
        error = "game '" + game + "' has no " + root + "/scenes/main.lua (run from the repo root)";
        return false;
    }
    this->gameName = game;
    this->gameRoot = root;
    currentGameRoot() = root;
    this->sceneLoader->setGameRoot(root);
    return true;
}

// <raiz>/game.lua es opcional: return { title=, width=, height=, logical_size={ w=, h= }, pixel_perfect= }
void Game::loadGameConfig() {
    const std::string path = this->gameRoot + "/game.lua";
    if (!std::filesystem::is_regular_file(path)) {
        return;
    }
    sol::state cfgLua;
    cfgLua.open_libraries(sol::lib::base);
    sol::protected_function_result result = cfgLua.safe_script_file(path, sol::script_pass_on_error);
    if (!result.valid() || result.get_type() != sol::type::table) {
        std::cout << "[Game] " << path << " must return a table; using defaults" << std::endl;
        return;
    }
    sol::table cfg = result;
    this->windowTitle = cfg.get_or<std::string>("title", this->windowTitle);
    this->configWidth = cfg.get_or("width", 0);
    this->configHeight = cfg.get_or("height", 0);
    // logical_size es opcional; solo cuenta si ademas pixel_perfect = true (ver init)
    sol::optional<sol::table> logical = cfg["logical_size"];
    if (logical) {
        this->configLogicalW = logical->get_or("w", 0);
        this->configLogicalH = logical->get_or("h", 0);
    }
    this->configPixelPerfect = cfg.get_or("pixel_perfect", false);
}

// Ajustes de audio en settings.json (ver Util/Settings.hpp): { "audio": { "buses": { "music": 0.5 } } }
std::string Game::settingsFile() const {
    return settings::settingsPath(this->gameName, this->gameRoot);
}

void Game::loadAudioSettings() {
    nlohmann::json j = settings::read(this->settingsFile());
    if (!j.contains("audio") || !j.at("audio").is_object()) return;

    const nlohmann::json& audio = j.at("audio");
    if (!audio.contains("buses") || !audio.at("buses").is_object()) return;

    for (const auto& entry : audio.at("buses").items()) {
        audiobus::Bus bus = audiobus::Bus::Sfx;
        if (!audiobus::parseBus(entry.key(), bus)) continue;
        if (!entry.value().is_number()) continue;

        this->audioManager->setBusVolume(bus, entry.value().get<double>());
    }
}

void Game::saveAudioSettings() {
    const std::string path = this->settingsFile();
    // Se parte del archivo actual para no borrar lo que no es de audio
    nlohmann::json j = settings::read(path);
    nlohmann::json& audio = j["audio"];
    if (!audio.is_object()) audio = nlohmann::json::object();
    nlohmann::json& buses = audio["buses"];
    if (!buses.is_object()) buses = nlohmann::json::object();

    for (int i = 0; i < audiobus::BUS_COUNT; i++) {
        audiobus::Bus bus = static_cast<audiobus::Bus>(i);
        // Dos decimales: el float del volumen no deja 0.30000001 en el archivo
        double value = std::round(static_cast<double>(this->audioManager->getBusVolume(bus)) * 100.0) / 100.0;
        buses[audiobus::busName(bus)] = value;
    }

    if (!settings::write(path, j)) {
        std::cout << "[Game] Could not write settings to " << path << std::endl;
    }
    this->audioSettingsDirty = false;
}

void Game::markAudioSettingsDirty() {
    this->audioSettingsDirty = true;
    this->audioSettingsDirtyAt = SDL_GetTicks();
}

// Partiendo del ducking actual, aplica los campos presentes en la tabla. buses reemplaza la lista de buses
void Game::applyDuckTable(const sol::table& opts) {
    audiobus::DuckConfig config = this->audioManager->getDuckConfig();
    config.enabled = opts.get_or<bool>("enabled", config.enabled);
    config.amount = opts.get_or<float>("amount", config.amount);
    config.fadeMs = opts.get_or<int>("fade_ms", config.fadeMs);

    sol::optional<sol::table> buses = opts.get<sol::optional<sol::table>>("buses");
    if (buses) {
        for (bool& listed : config.buses) listed = false;
        for (const auto& entry : *buses) {
            if (!entry.second.is<std::string>()) continue;
            std::string name = entry.second.as<std::string>();

            audiobus::Bus bus = audiobus::Bus::Sfx;
            if (!audiobus::parseBus(name, bus)) {
                std::cout << "[Audio] set_ducking: unknown bus '" << name << "', ignored" << std::endl;
                continue;
            }
            if (bus == audiobus::Bus::Voice) {
                std::cout << "[Audio] set_ducking: the voice bus is never ducked, ignored" << std::endl;
                continue;
            }
            config.buses[static_cast<int>(bus)] = true;
        }
    }

    this->audioManager->setDuckConfig(config);
}

std::string Game::buildPackagePath() const {
    const std::string scripts = this->gameRoot + "/scripts";
    std::string path = scripts + "/?.lua;";
    std::vector<std::string> dirs;
    std::error_code ec;
    for (const auto& entry : std::filesystem::directory_iterator(scripts, ec)) {
        if (entry.is_directory() && entry.path().filename() != "prefabs") {
            dirs.push_back(entry.path().filename().string());
        }
    }
    std::sort(dirs.begin(), dirs.end());
    for (const auto& d : dirs) path += scripts + "/" + d + "/?.lua;";
    path += std::string(COMMON_DIR) + "/scripts/?.lua;";
    return path;
}

std::string Game::entryScenePath() const {
    return this->gameRoot + "/scenes/main.lua";
}

void Game::init() {
    this->loadGameConfig();

    if (SDL_Init(SDL_INIT_EVERYTHING) != 0) {
        std::cout << "[Game] Error initializing SDL" << std::endl;
        return;
    }

    if (TTF_Init() != 0) {
        std::cout << "[Game] Error initializing SDL TTF" << std::endl;
        return;
    }

    // Sin dispositivo de audio el motor sigue: las llamadas de audio quedan en no-op
    this->audioManager->init();
    // Despues de init: los volumenes guardados se aplican al mezclador ya abierto
    this->loadAudioSettings();

    SDL_DisplayMode displayMode;
    SDL_GetCurrentDisplayMode(0, &displayMode);

    const bool customSize = this->configWidth > 0 && this->configHeight > 0;
    this->nativeWidth = customSize ? this->configWidth : displayMode.w;
    this->nativeHeight = customSize ? this->configHeight : displayMode.h;

    // Pixel-perfect: logical_size > 0 y pixel_perfect = true. Sin pixel_perfect, logical_size se ignora
    const bool hasLogical = this->configLogicalW > 0 && this->configLogicalH > 0;
    if (hasLogical && !this->configPixelPerfect) {
        std::cout << "[Game] logical_size sin pixel_perfect = true: ignorado" << std::endl;
    }
    this->pixelPerfect = hasLogical && this->configPixelPerfect;

    if (this->pixelPerfect) {
        this->logicalWidth = this->configLogicalW;
        this->logicalHeight = this->configLogicalH;
        // Lua ve el tamaño logico; la ventana nativa se crea aparte
        this->windowWidth = this->logicalWidth;
        this->windowHeight = this->logicalHeight;
    } else {
        this->windowWidth = this->nativeWidth;
        this->windowHeight = this->nativeHeight;
    }

    this->camera = { 0, 0, this->windowWidth, this->windowHeight };

    window = SDL_CreateWindow(
        this->windowTitle.c_str(),
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        this->nativeWidth,
        this->nativeHeight,
        customSize ? SDL_WINDOW_SHOWN : (SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN_DESKTOP)
    );

    if (!this->window) {
        std::cout << "[Game] Error creating window" << std::endl;
        return;
    }
    
    if (this->pixelPerfect) {
        // Sin filtrado: el pixel art se escala al vecino mas cercano (nitido)
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    }

    renderer = SDL_CreateRenderer(this->window,-1,0);

    if (!this->renderer) {
        std::cout << "[Game] Error creating renderer" << std::endl;
        return;
    }

    // SDL_RenderSetLogicalSize necesita SDL >= 2.0.5; si falla, se vuelve al modo normal
    if (this->pixelPerfect && SDL_RenderSetLogicalSize(this->renderer, this->logicalWidth, this->logicalHeight) != 0) {
        std::cout << "[Game] SDL_RenderSetLogicalSize failed, pixel_perfect off: " << SDL_GetError() << std::endl;
        this->pixelPerfect = false;
        this->windowWidth = this->nativeWidth;
        this->windowHeight = this->nativeHeight;
        this->camera = { 0, 0, this->windowWidth, this->windowHeight };
    }
    this->updateLayout();

    this->isRunning = true;
}

void Game::setup() {
    this->registry->addSystem<RenderSystem>();
    this->registry->addSystem<MovementSystem>();
    this->registry->addSystem<GravitySystem>();
    this->registry->addSystem<BoxColliderSystem>();
    this->registry->addSystem<CollisionSystem>();
    this->registry->addSystem<DamageSystem>();
    this->registry->addSystem<AnimationSystem>();
    this->registry->addSystem<ScriptSystem>();
    this->registry->addSystem<NetSyncSystem>();
    this->registry->addSystem<TextRenderSystem>();
    this->registry->addSystem<PathRenderSystem>();
    this->registry->addSystem<ColliderRenderSystem>();
    this->registry->addSystem<BoxColliderRenderSystem>();
    this->registry->addSystem<SpatialAudioSystem>();
    this->registry->addSystem<LightingSystem>();

    // Una entidad muerta se borra de los pares de trigger sin generar Exit
    this->registry->onEntityKilled([this](Entity entity) {
        this->registry->getSystem<CollisionSystem>().forgetEntity(entity.getId());
        // Sus emisores de sonido callan con ella
        this->audioManager->stopEmittersFollowing(entity.getId());
    });

    this->lua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string, sol::lib::package);
    this->lua["package"]["path"] = this->buildPackagePath() +
        this->lua["package"]["path"].get<std::string>();
    this->registry->getSystem<ScriptSystem>().createLuaBiding(this->lua);
    this->networkScripting = std::make_unique<NetworkScripting>(*this->netClient,
        *this->networkRegistry, *this->registry, this->lua, *this->sceneLoader,
        this->gameRoot + "/scripts/prefabs/");

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

    this->loadScene(this->entryScenePath());
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

void Game::loadScene(const std::string& requestedScene) {
    // Se resuelve antes de comparar: currentScene guarda siempre la ruta resuelta
    const std::string scenePath = resolveGamePath(this->gameRoot, requestedScene);
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
    // Las voces y la musica son de la escena que se descarga (los assets se conservan por id)
    this->audioManager->stopAll();
    // El ducking es de la escena: vuelve al por defecto antes de leer scene.audio.duck
    this->audioManager->resetDuckConfig();
    // El oyente fijado con set_listener era una entidad de la escena que se descarga
    this->listenerEntity = -1;
    this->textBuffer.clear();
    this->rectBuffer.clear();
    this->spriteBuffer.clear();
    this->camera.x = 0;
    this->camera.y = 0;
    // El area activa es de la escena que se descarga (set_active_area la vuelve a fijar)
    activeArea().enabled = false;
    // La geometria estatica y los pares de trigger tambien son de la escena
    this->staticWorld.clear();
    this->registry->getSystem<CollisionSystem>().resetTriggers();
    // El tile map y el orden por Y tambien son de la escena
    this->tileMap.reset();
    this->ySort = false;
    // Sin luces y con ambiente blanco hasta que la escena diga otra cosa
    this->registry->getSystem<LightingSystem>().reset();

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

    // scene.audio.duck es opcional: sin el, la escena usa el ducking por defecto (ya repuesto)
    sol::object sceneObj = this->lua["scene"];
    if (sceneObj.is<sol::table>()) {
        sol::table scene = sceneObj.as<sol::table>();
        sol::optional<sol::table> audio = scene["audio"];
        if (audio) {
            sol::optional<sol::table> duck = (*audio)["duck"];
            if (duck) this->applyDuckTable(*duck);
        }
        // scene.lighting.ambient = { r, g, b } es opcional: sin el, la escena arranca sin oscuridad
        sol::optional<sol::table> lightingDef = scene["lighting"];
        if (lightingDef) {
            sol::optional<sol::table> amb = (*lightingDef)["ambient"];
            if (amb) {
                this->registry->getSystem<LightingSystem>().setAmbient(
                    (*amb)["r"].get_or(255), (*amb)["g"].get_or(255), (*amb)["b"].get_or(255), 0.0f);
            }
        }
    }
}

bool Game::loadTileMap(const std::string& path, double x, double y, std::string& error) {
    tmx::Result parsed = tmx::loadFile(resolveGamePath(this->gameRoot, path));
    if (!parsed.ok) {
        error = parsed.error;
        return false;
    }
    tilemap::BuildOptions options;
    options.x = x;
    options.y = y;
    tilemap::BuildResult built = tilemap::build(parsed.map, options);
    if (!built.ok) {
        error = built.error;
        return false;
    }
    for (const std::string& warning : built.warnings) {
        std::cout << "[TileMap] " << warning << std::endl;
    }

    auto system = std::make_unique<TileMapRenderSystem>(std::move(built.map));
    system->loadTextures(this->renderer, *this->assetManager);
    // La segunda llamada reemplaza al mapa anterior
    this->tileMap = std::move(system);
    this->ySort = true;
    return true;
}

void Game::unloadTileMap() {
    this->tileMap.reset();
}

// Escala entera y letterbox segun el tamaño de salida actual del renderer
void Game::updateLayout() {
    if (!this->pixelPerfect) return;
    int outW = 0;
    int outH = 0;
    SDL_GetRendererOutputSize(this->renderer, &outW, &outH);
    this->layout = pixelperfect::computeLayout(outW, outH, this->logicalWidth, this->logicalHeight);
}

void Game::processInput() {
    int mouseX, mouseY;
    SDL_GetMouseState(&mouseX, &mouseY);
    if (this->pixelPerfect) {
        // Sin ALLOW_HIGHDPI los puntos de SDL son pixeles de salida: se pasa a coordenadas logicas.
        // No se recorta: sobre las barras del letterbox el valor puede ser negativo o mayor que el logico
        mouseX = pixelperfect::windowToLogical(mouseX, this->layout.offsetX, this->layout.scale);
        mouseY = pixelperfect::windowToLogical(mouseY, this->layout.offsetY, this->layout.scale);
    }
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

// Dibuja los comandos de draw_image de una capa (coordenadas de pantalla).
// "view" pasa las coordenadas logicas a pixeles nativos (identidad si el modo esta apagado)
void Game::drawSprites(int layer, const pixelperfect::Layout& view) {
    for (const auto& cmd : this->spriteBuffer.getCommands()) {
        if (cmd.layer != layer) continue;
        SDL_Texture* texture = this->assetManager->getTexture(cmd.assetId);
        if (texture == nullptr) continue;

        SDL_Rect dst = {
            view.offsetX + cmd.x * view.scale,
            view.offsetY + cmd.y * view.scale,
            cmd.w * view.scale,
            cmd.h * view.scale
        };
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
        SDL_SetTextureAlphaMod(texture, cmd.alpha);
        SDL_RenderCopyEx(this->renderer, texture, cmd.hasSrc ? &cmd.src : nullptr, &dst, cmd.angle, nullptr,
          SDL_FLIP_NONE);
        SDL_SetTextureAlphaMod(texture, 255);
    }
}

// Paneles del HUD (rectangulos). World: solo los de mundo (con camara); Hud: solo los de pantalla,
// pasados a pixeles nativos con el layout; All: todos, como antes del modo pixel-perfect
void Game::drawRects(RectPass pass) {
    SDL_SetRenderDrawBlendMode(this->renderer, SDL_BLENDMODE_BLEND);
    for (const auto& rect : this->rectBuffer.getCommands()) {
        if (pass == RectPass::World && !rect.isWorldSpace) continue;
        if (pass == RectPass::Hud && rect.isWorldSpace) continue;

        SDL_Rect sdlRect = { rect.x, rect.y, rect.w, rect.h };
        if (rect.isWorldSpace) {
            sdlRect.x -= this->camera.x;
            sdlRect.y -= this->camera.y;
        }
        if (pass == RectPass::Hud) {
            sdlRect.x = pixelperfect::logicalToNative(sdlRect.x, this->layout.offsetX, this->layout.scale);
            sdlRect.y = pixelperfect::logicalToNative(sdlRect.y, this->layout.offsetY, this->layout.scale);
            sdlRect.w *= this->layout.scale;
            sdlRect.h *= this->layout.scale;
        }

        SDL_SetRenderDrawColor(this->renderer, rect.color.r, rect.color.g, rect.color.b, rect.color.a);
        if (rect.filled) {
            SDL_RenderFillRect(this->renderer, &sdlRect);
        } else {
            SDL_RenderDrawRect(this->renderer, &sdlRect);
        }
    }
}

// Barras del letterbox (pixeles nativos): solo si sobra espacio a algun lado
void Game::drawLetterbox() {
    if (!this->pixelPerfect) return;
    int outW = 0;
    int outH = 0;
    SDL_GetRendererOutputSize(this->renderer, &outW, &outH);

    SDL_SetRenderDrawBlendMode(this->renderer, SDL_BLENDMODE_NONE);
    SDL_SetRenderDrawColor(this->renderer, 10, 10, 18, 255);
    if (this->layout.offsetX > 0) {
        SDL_Rect left = { 0, 0, this->layout.offsetX, outH };
        SDL_Rect right = { outW - this->layout.offsetX, 0, this->layout.offsetX, outH };
        SDL_RenderFillRect(this->renderer, &left);
        SDL_RenderFillRect(this->renderer, &right);
    }
    if (this->layout.offsetY > 0) {
        SDL_Rect top = { 0, 0, outW, this->layout.offsetY };
        SDL_Rect bottom = { 0, outH - this->layout.offsetY, outW, this->layout.offsetY };
        SDL_RenderFillRect(this->renderer, &top);
        SDL_RenderFillRect(this->renderer, &bottom);
    }
}

void Game::render() {
    // Casi negro: fondo de espacio
    SDL_SetRenderDrawColor(this->renderer, 10, 10, 18, 255);
    SDL_RenderClear(this->renderer);

    // Pasada del mundo: todo se dibuja en coordenadas logicas y SDL lo escala entero
    if (this->pixelPerfect) {
        this->updateLayout();
        SDL_RenderSetLogicalSize(this->renderer, this->logicalWidth, this->logicalHeight);
        SDL_RenderSetIntegerScale(this->renderer, SDL_TRUE);
    }

    // Imagenes de la capa "back" (fondos, nubes): bajo las entidades
    this->drawSprites(0);

    // Orden del mundo: suelo (tiles y sprites "ground"), entidades y tiles altos
    // (por Y si hay mapa o set_y_sort; si no, en orden de insercion) y por ultimo
    // lo que va por encima. Sin tile map y con ySort apagado el resultado es el de siempre
    RenderSystem& renderSystem = this->registry->getSystem<RenderSystem>();
    renderSystem.collect(this->assetManager, this->camera);
    if (this->tileMap) this->tileMap->drawPass(this->renderer, this->camera, tilemap::Pass::Ground);
    renderSystem.drawLayer(this->renderer, SpriteLayer::Ground);
    if (this->ySort) {
        renderSystem.drawSorted(this->renderer, this->camera, this->tileMap.get());
    } else {
        if (this->tileMap) this->tileMap->drawPass(this->renderer, this->camera, tilemap::Pass::YSort);
        renderSystem.drawLayer(this->renderer, SpriteLayer::World);
    }
    if (this->tileMap) this->tileMap->drawPass(this->renderer, this->camera, tilemap::Pass::Above);
    renderSystem.drawLayer(this->renderer, SpriteLayer::Above);
    // La iluminacion va despues de los rectangulos de mundo (Quebrada dibuja ahi su mundo) y antes del HUD

    // La trayectoria va encima de los sprites pero debajo del HUD de texto
    this->registry->getSystem<PathRenderSystem>().update(this->renderer, this->camera, this->deltaTime);

    // Overlay de debug: se salta por completo cuando está apagado
    if (this->showColliders) {
        this->registry->getSystem<ColliderRenderSystem>().update(this->renderer, this->camera);
        this->registry->getSystem<BoxColliderRenderSystem>().update(this->renderer, this->camera);
        this->registry->getSystem<BoxColliderRenderSystem>().drawStatic(this->renderer, this->camera, this->staticWorld);
    }

    // Imagenes de la capa "front": sobre las entidades y bajo el HUD
    this->drawSprites(1);

    LightingSystem& lighting = this->registry->getSystem<LightingSystem>();
    if (this->pixelPerfect) {
        // Rectangulos de mundo: aun en la pasada logica
        this->drawRects(RectPass::World);
        // Luz: multiplica el mundo en coordenadas logicas; el HUD de abajo no se oscurece
        lighting.render(this->renderer, this->camera);

        // Pasada nativa: barras del letterbox, HUD y sprites de HUD en pixeles de la ventana
        SDL_RenderSetLogicalSize(this->renderer, 0, 0);
        this->drawLetterbox();
        this->drawRects(RectPass::Hud);
        this->drawSprites(2, this->layout);
    } else {
        // Paneles del HUD (rectangulos): van antes del texto para que el texto quede encima
        if (lighting.isActive()) {
            // Con luz: mundo, luz y luego HUD (fuera de pixel-perfect el layout es la identidad)
            this->drawRects(RectPass::World);
            lighting.render(this->renderer, this->camera);
            this->drawRects(RectPass::Hud);
        } else {
            this->drawRects(RectPass::All);
        }

        // Imagenes de la capa "hud": sobre los paneles del HUD (iconos del minimapa)
        this->drawSprites(2);
    }

    // El texto va después de los sprites para que quede encima (en pixeles nativos)
    this->registry->getSystem<TextRenderSystem>().update(this->renderer, this->assetManager,
        this->camera, this->textBuffer, this->layout);

    // Los comandos duran un frame: los scripts los vuelven a pedir en el próximo update()
    this->textBuffer.clear();
    this->rectBuffer.clear();
    this->spriteBuffer.clear();

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
    this->audioManager->update();
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
    this->registry->getSystem<ScriptSystem>().subscribeToTriggerEvent(this->eventManager);

    this->registry->update();
    this->registry->getSystem<ScriptSystem>().update(this->lua);
    // Replicacion de estado: envia lo propio y corrige lo ajeno antes de simular
    for (auto& msg : this->registry->getSystem<NetSyncSystem>().update(
            deltaTime, *this->networkRegistry, this->netClient->isOnline())) {
        this->netClient->send(std::move(msg));
    }
    this->registry->getSystem<AnimationSystem>().update(deltaTime);
    if (this->tileMap) this->tileMap->advance(deltaTime);
    // La gravedad suma a la velocidad antes de integrar el movimiento
    this->registry->getSystem<GravitySystem>().update(deltaTime);
    this->registry->getSystem<MovementSystem>().update(deltaTime);
    // Movers con caja: barrido contra paredes y cajas solidas (MovementSystem
    // solo les actualizo la velocidad)
    this->registry->getSystem<BoxColliderSystem>().resolveMovers(deltaTime, this->staticWorld);
    this->registry->getSystem<CollisionSystem>().update(this->eventManager,
        this->registry->getSystem<BoxColliderSystem>().getEntities());
    // Al final: el oyente y los emisores ya estan en su posicion de este frame
    this->updateSpatialAudio(deltaTime);
    this->registry->getSystem<LightingSystem>().update(deltaTime);
}

void Game::updateSpatialAudio(double dt) {
    // Entity guarda el puntero al registry; un id suelto hay que completarlo
    auto entityFromId = [this](int id) {
        Entity entity(id);
        entity.registry = this->registry.get();
        return entity;
    };

    // Oyente: set_listener -> player_entity de Lua -> centro de la camara
    float listenerX = this->camera.x + this->camera.w / 2.0f;
    float listenerY = this->camera.y + this->camera.h / 2.0f;
    bool found = false;

    if (this->listenerEntity >= 0) {
        Entity entity = entityFromId(this->listenerEntity);
        if (this->registry->hasComponent<TransformComponent>(entity)) {
            glm::vec2 center = SpatialAudioSystem::entityCenter(entity);
            listenerX = center.x;
            listenerY = center.y;
            found = true;
        }
    }

    if (!found) {
        sol::object player = this->lua["player_entity"];
        if (player.is<Entity>()) {
            Entity entity = player.as<Entity>();
            if (this->registry->hasComponent<TransformComponent>(entity)) {
                glm::vec2 center = SpatialAudioSystem::entityCenter(entity);
                listenerX = center.x;
                listenerY = center.y;
            }
        }
    }

    // Buses y ducking antes que las voces espaciales: el mismo frame usa el volumen nuevo
    this->audioManager->updateBuses(dt);
    // Los ajustes se guardan cuando el jugador deja de moverlos (500 ms sin cambios)
    if (this->audioSettingsDirty && SDL_GetTicks() - this->audioSettingsDirtyAt >= 500) {
        this->saveAudioSettings();
    }

    // El oyente se fija antes de arrancar voces nuevas para que no suenen un frame con el viejo
    this->audioManager->setListener(listenerX, listenerY);
    this->registry->getSystem<SpatialAudioSystem>().update(*this->audioManager);

    this->audioManager->updateSpatial(listenerX, listenerY, dt,
        [&](int entityId, float& x, float& y) {
            Entity entity = entityFromId(entityId);
            if (!this->registry->hasComponent<TransformComponent>(entity)) return false;
            glm::vec2 center = SpatialAudioSystem::entityCenter(entity);
            // Un SoundEmitterComponent puede desplazar la fuente respecto al centro
            if (this->registry->hasComponent<SoundEmitterComponent>(entity)) {
                center += entity.getComponent<SoundEmitterComponent>().offset;
            }
            x = center.x;
            y = center.y;
            return true;
        });
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
    this->registry->getSystem<LightingSystem>().releaseTextures();
    this->tileMap.reset();
    // Los volumenes de bus se guardan antes de cerrar, aunque el ultimo cambio sea reciente
    if (this->audioSettingsDirty) this->saveAudioSettings();
    // Los canales se detienen antes de liberar los chunks; el mezclador se cierra
    // despues, para que Mix_FreeMusic aun tenga sus decodificadores cargados
    this->audioManager->stopAll();
    this->assetManager->clearAll();
    this->audioManager->shutdown();

    SDL_DestroyRenderer(this->renderer);
    SDL_DestroyWindow(this->window);
    TTF_Quit();
    SDL_Quit();
}

Game& Game::getInstance() {
    static Game game;
    return game;
}