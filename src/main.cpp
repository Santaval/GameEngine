#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include "Game/Game.hpp"

int main(int argc, char* argv[]) {
    std::cout << "Hello from Engine" << std::endl;

    // Multijugador opcional: --server <url>, --server=<url> o GAME_SERVER.
    // Sin ninguno de los tres el juego corre offline como siempre.
    std::string serverUrl;
    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--server") == 0 && i + 1 < argc) {
            serverUrl = argv[++i];
        } else if (std::strncmp(argv[i], "--server=", 9) == 0) {
            serverUrl = argv[i] + 9;
        }
    }
    if (serverUrl.empty()) {
        const char* env = std::getenv("GAME_SERVER");
        if (env) {
            serverUrl = env;
        }
    }

    Game& game = Game::getInstance();
    game.setServerUrl(serverUrl);
    game.init();
    game.run();
    game.destroy();
    return 0;
}
