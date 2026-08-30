#include "Game.hpp"
#include <iostream>
#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Systems/RenderSystem.hpp"
#include "../Systems/MovementSystem.hpp"

Game::Game() {
    this->assetManager = std::make_unique<AssetManager>();
    this->registry = std::make_unique<Registry>(); 
    std::cout << "[Game] Game init" << std::endl;
}

Game::~Game() {
    this->assetManager.reset();
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
    this->assetManager->addTexture(this->renderer, "enemy_allan", "./assets/images/enemy_allan.png");
    
    Entity enemy = this->registry->createEntity();

    enemy.addComponent<RigidBodyComponent>(glm::vec2(50.0, 0));
    enemy.addComponent<SpriteComponent>("enemy_allan", 16, 16, 0, 0);
    enemy.addComponent<TransformComponent>(glm::vec2(100.0, 100.0), glm::vec2(2.0, 2.0), 0.0);
}


void Game::processInput() {
    SDL_Event sdlEvent;
    while(SDL_PollEvent(&sdlEvent)) {

        switch(sdlEvent.type) {

            case SDL_QUIT:
                this->isRunning = false;
                break;
            case SDL_KEYDOWN:
                if(sdlEvent.key.keysym.sym == SDLK_ESCAPE) {
                    this->isRunning = false;
                }
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

    this->milisecsPreviousFrame = SDL_GetTicks();

    this->registry->update();
    this->registry->getSystem<MovementSystem>().update(deltaTime);
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