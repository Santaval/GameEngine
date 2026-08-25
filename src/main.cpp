#include <iostream>
#include "Game/Game.hpp"

int main() {
    std::cout << "Hello from Engine" << std::endl;

    Game& game = Game::getInstance();
    game.init();
    game.run();
    game.destroy();
    return 0;
}