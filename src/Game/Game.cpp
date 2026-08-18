#include "Game.hpp"
#include <iostream>


Game::Game() {
    std::cout << "[Game] Game init" << std::endl;
}

Game::~Game() {
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
    while(this->isRunning) {
        this->processInput();
        // this->update();
        this->render();
    }
}

void Game::destroy() {
    TTF_Quit();
    SDL_Quit();
}