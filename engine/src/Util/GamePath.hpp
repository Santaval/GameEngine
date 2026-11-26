#pragma once

#include <string>

// Rutas de juego: donde viven los juegos y los recursos compartidos del motor.
// Todas son relativas al directorio de trabajo (la raiz del repo).
inline const char* const GAMES_DIR = "./games";
inline const char* const COMMON_DIR = "./engine/common";
inline const char* const DEFAULT_GAME = "aval";

// Raiz del juego cargado (la fija Game::setGame). Permite a los bindings de Lua
// resolver rutas sin depender de Game.
inline std::string& currentGameRoot() {
    static std::string root = std::string(GAMES_DIR) + "/" + DEFAULT_GAME;
    return root;
}

// Resuelve una ruta escrita en un script de juego:
//   @common/x         -> ./engine/common/x   (recursos compartidos del motor)
//   /abs, ./x, ../x   -> sin cambios         (absoluta o relativa al cwd)
//   cualquier otra    -> <raiz del juego>/x
inline std::string resolveGamePath(const std::string& gameRoot, const std::string& p) {
    if (p.rfind("@common/", 0) == 0) {
        return std::string(COMMON_DIR) + "/" + p.substr(8);
    }
    if (p.empty() || p[0] == '/' || p.rfind("./", 0) == 0 || p.rfind("../", 0) == 0) {
        return p;
    }
    return gameRoot + "/" + p;
}
