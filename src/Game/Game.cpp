#include "Game.hpp"
#include <iostream>
#include "../Components/TransformComponent.hpp"


Game::Game() {
    this->assetManager = srd::make_unique<AssetManager>();
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
    Entity e = this->registry->createEntity();
    e.addComponent<TransformComponent>(glm::vec2(100.0, 100.0), glm::vec2(1.0, 1.0), 0.0);
}


void Game::processInput() {
    SDL_Event sdlEvent;
    while(SDL_PollEvent(&sdlEvent)) {

        switch(sdlEvent.type) {

            case SDL_QUIT:
                this->isRunning = false;

            default:
                break;
        }
    }
}

void Game::render() {
    SDL_SetRenderDrawColor(this->renderer, 31, 31, 31, 255);
    SDL_RenderClear(this->renderer);

    SDL_RenderPresent(this->renderer);
}

void Game::update() {
    
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