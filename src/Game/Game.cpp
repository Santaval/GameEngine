#include "Game.hpp"

#include <iostream>

#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/ScriptComponent.hpp"

#include "../Systems/CollisionSystem.hpp"
#include "../Systems/RenderSystem.hpp"
#include "../Systems/MovementSystem.hpp"
#include "../Systems/DamageSystem.hpp"
#include "../Systems/AnimationSystem.hpp"
#include "../Systems/ScriptSystem.hpp"

Game::Game() {
    this->assetManager = std::make_unique<AssetManager>();
    this->eventManager = std::make_unique<EventManager>();
    this->controllerManager = std::make_unique<ControllerManager>();
    this->registry = std::make_unique<Registry>(); 

    this->sceneLoader = std::make_unique<SceneLoader>(); 
    std::cout << "[Game] Game init" << std::endl;
}

Game::~Game() {
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

    this->windowWidth = 800;
    this->windowHeight = 600;

    window = SDL_CreateWindow(
        "Engine",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        this->windowWidth,
        this->windowHeight,
        SDL_WINDOW_SHOWN
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
    this->registry->addSystem<CollisionSystem>();
    this->registry->addSystem<DamageSystem>();
    this->registry->addSystem<AnimationSystem>();
    this->registry->addSystem<ScriptSystem>();

    this->lua.open_libraries(sol::lib::base, sol::lib::math);
    this->registry->getSystem<ScriptSystem>().createLuaBiding(this->lua);
    
    this->sceneLoader->load("./assets/scripts/scenes/scene_01.lua", this->lua, this->assetManager,
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
    SDL_SetRenderDrawColor(this->renderer, 31, 31, 31, 255);
    SDL_RenderClear(this->renderer);

    this->registry->getSystem<RenderSystem>().update(this->renderer, this->assetManager);

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

    // Reset events subscriptions
    this->eventManager->reset();
    this->registry->getSystem<DamageSystem>().subscribeToCollisionEvent(this->eventManager);

    this->registry->update();
    this->registry->getSystem<ScriptSystem>().update(this->lua);
    this->registry->getSystem<AnimationSystem>().update();
    this->registry->getSystem<MovementSystem>().update(deltaTime);
    this->registry->getSystem<CollisionSystem>().update(this->eventManager);
}


void Game::run() {
    this->setup();

    while(this->isRunning) {
        this->processInput();
        this->update();
        this->render();
    }
}

void Game::destroy() {
    SDL_DestroyRenderer(this->renderer);
    SDL_DestroyWindow(this->window);
    TTF_Quit();
    SDL_Quit();
}

Game& Game::getInstance() {
    static Game game;
    return game;
}