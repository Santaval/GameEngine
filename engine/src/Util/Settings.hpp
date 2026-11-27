#pragma once

#include <SDL2/SDL.h>
#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>

// Ajustes persistentes del jugador (volumen de buses, etc.) en un settings.json.
// Solo cabecera. La ruta sale de SDL_GetPrefPath (carpeta de usuario del sistema);
// si SDL no la da, se usa la carpeta del juego.

namespace settings {

// Ruta del settings.json: <prefPath>/settings.json, o <gameRoot>/settings.json
inline std::string settingsPath(const std::string& gameName, const std::string& gameRoot) {
  char* pref = SDL_GetPrefPath("gameEngine", gameName.c_str());
  if (pref) {
    std::string path = std::string(pref) + "settings.json";
    SDL_free(pref);
    return path;
  }
  return (std::filesystem::path(gameRoot) / "settings.json").string();
}

// Lee el archivo como objeto JSON. Si no existe, no es JSON valido o no es un
// objeto, devuelve un objeto vacio (los ajustes nunca tumban el juego)
inline nlohmann::json read(const std::string& path) {
  std::ifstream in(path);
  if (!in) return nlohmann::json::object();

  nlohmann::json j = nlohmann::json::parse(in, nullptr, false);
  if (j.is_discarded() || !j.is_object()) return nlohmann::json::object();
  return j;
}

// Escribe a un temporal y lo renombra encima: un corte a mitad no deja el archivo
// a medias. Devuelve false si algo falla
inline bool write(const std::string& path, const nlohmann::json& j) {
  std::string tmp = path + ".tmp";
  {
    std::ofstream out(tmp, std::ios::trunc);
    if (!out) return false;
    out << j.dump(2);
    if (!out) return false;
  }

  std::error_code ec;
  std::filesystem::rename(tmp, path, ec);
  return !ec;
}

}  // namespace settings
