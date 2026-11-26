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

    // Juego a cargar: --game <nombre>, --game=<nombre> o GAME.
    // Sin ninguno corre el juego por defecto (assets/ tal cual).
    std::string gameName;
    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--game") == 0 && i + 1 < argc) {
            gameName = argv[++i];
        } else if (std::strncmp(argv[i], "--game=", 7) == 0) {
            gameName = argv[i] + 7;
        }
    }
    if (gameName.empty()) {
        const char* env = std::getenv("GAME");
        if (env) {
            gameName = env;
        }
    }

    Game& game = Game::getInstance();
    std::string gameError;
    if (!game.setGame(gameName, gameError)) {
        std::cerr << "[Game] " << gameError << std::endl;
        return 1;
    }
    game.setServerUrl(serverUrl);
    game.init();
    game.run();
    game.destroy();
    return 0;
}
