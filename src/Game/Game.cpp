#include "Game.hpp"

#include <iostream>

#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/AnimationComponent.hpp"

#include "../Systems/CollisionSystem.hpp"
#include "../Systems/RenderSystem.hpp"
#include "../Systems/MovementSystem.hpp"
#include "../Systems/DamageSystem.hpp"
#include "../Systems/AnimationSystem.hpp"

Game::Game() {
    this->assetManager = std::make_unique<AssetManager>();
    this->eventManager = std::make_unique<EventManager>();
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
    this->registry->addSystem<CollisionSystem>();
    this->registry->addSystem<DamageSystem>();
    this->registry->addSystem<AnimationSystem>();
    this->assetManager->addTexture(this->renderer, "spaceship-idle", "./assets/images/spaceship-idle-ss.png");
    this->assetManager->addTexture(this->renderer, "spaceship-attack", "./assets/images/spaceship-attack-ss.png");
    this->assetManager->addTexture(this->renderer, "spaceship-recollection", "./assets/images/spaceship-recollection-ss.png");
    
    Entity enemy1 = this->registry->createEntity();
    enemy1.addComponent<AnimationComponent>(4, 10);
    enemy1.addComponent<RigidBodyComponent>(glm::vec2(0.0, 0));
    enemy1.addComponent<SpriteComponent>("spaceship-idle", 443.5, 530, 0, 165);
    enemy1.addComponent<TransformComponent>(glm::vec2(200.0, 100.0), glm::vec2(0.2, 0.2), 0.0);
    enemy1.addComponent<CircleColliderComponent>(8, 16, 16);

    Entity enemy2 = this->registry->createEntity();
    enemy2.addComponent<AnimationComponent>(4, 10);
    enemy2.addComponent<RigidBodyComponent>(glm::vec2(0.0, 0));
    enemy2.addComponent<SpriteComponent>("spaceship-attack", 443.5, 530, 0, 165);
    enemy2.addComponent<TransformComponent>(glm::vec2(400.0, 100.0), glm::vec2(0.2, 0.2), 0.0);
    enemy2.addComponent<CircleColliderComponent>(8, 16, 16);

    Entity enemy3 = this->registry->createEntity();
    enemy3.addComponent<AnimationComponent>(4, 10);
    enemy3.addComponent<RigidBodyComponent>(glm::vec2(0.0, 0));
    enemy3.addComponent<SpriteComponent>("spaceship-recollection", 418, 600, 0, 125);
    enemy3.addComponent<TransformComponent>(glm::vec2(600.0, 100.0), glm::vec2(0.2, 0.2), 0.0);
    enemy3.addComponent<CircleColliderComponent>(8, 16, 16);

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

    // Reset events subscriptions
    this->eventManager->reset();
    this->registry->getSystem<DamageSystem>().subscribeToCollisionEvent(this->eventManager);

    this->registry->update();
    this->registry->getSystem<CollisionSystem>().update(this->eventManager);
    this->registry->getSystem<MovementSystem>().update(deltaTime);
    this->registry->getSystem<AnimationSystem>().update();
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