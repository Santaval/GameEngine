#pragma once

#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <system_error>

// Guardado de partidas en disco (issue #52). Solo cabecera y sin SDL: la carpeta
// la decide quien llama (SaveBindings usa SDL_GetPrefPath).
//
// Cada ranura son tres archivos en `dir`:
//   save_<slot>.json       el guardado actual
//   save_<slot>.json.bak   el guardado anterior (una copia de respaldo)
//   save_<slot>.json.tmp   temporal de escritura; nunca se lee
// Escribir nunca toca el archivo bueno hasta que el temporal esta completo: un corte
// a mitad deja el guardado anterior (o su .bak) utilizable.

namespace savefile {

// Nombre de ranura valido: 1..64 caracteres de [A-Za-z0-9_-] (nada de rutas)
inline bool validSlot(const std::string& slot) {
  if (slot.empty() || slot.size() > 64) return false;
  for (char c : slot) {
    bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
              c == '_' || c == '-';
    if (!ok) return false;
  }
  return true;
}

inline std::string slotPath(const std::string& dir, const std::string& slot) {
  return (std::filesystem::path(dir) / ("save_" + slot + ".json")).string();
}
inline std::string backupPath(const std::string& dir, const std::string& slot) {
  return slotPath(dir, slot) + ".bak";
}
inline std::string tempPath(const std::string& dir, const std::string& slot) {
  return slotPath(dir, slot) + ".tmp";
}

// Lee un archivo como objeto JSON; nullopt si no existe, esta roto o no es un objeto
inline std::optional<nlohmann::json> readFile(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return std::nullopt;
  nlohmann::json j = nlohmann::json::parse(in, nullptr, false);
  if (j.is_discarded() || !j.is_object()) return std::nullopt;
  return j;
}

// Guarda `data` (debe ser un objeto) en la ranura. false si algo falla; en ese caso
// el guardado anterior sigue intacto
inline bool write(const std::string& dir, const std::string& slot, const nlohmann::json& data) {
  if (!validSlot(slot)) {
    std::cerr << "[save] nombre de ranura invalido: '" << slot << "'" << std::endl;
    return false;
  }
  if (!data.is_object()) {
    std::cerr << "[save] el guardado debe ser una tabla" << std::endl;
    return false;
  }

  std::error_code ec;
  std::filesystem::create_directories(dir, ec);

  std::string text;
  try {
    // replace: un UTF-8 invalido no debe impedir guardar
    text = data.dump(2, ' ', false, nlohmann::json::error_handler_t::replace);
  } catch (const std::exception& e) {
    std::cerr << "[save] no se pudo serializar: " << e.what() << std::endl;
    return false;
  }

  std::string main = slotPath(dir, slot);
  std::string bak = backupPath(dir, slot);
  std::string tmp = tempPath(dir, slot);

  {
    std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
    if (!out) {
      std::cerr << "[save] no se pudo abrir " << tmp << std::endl;
      return false;
    }
    out << text;
    out.flush();
    if (!out) {
      std::cerr << "[save] fallo al escribir " << tmp << std::endl;
      out.close();
      std::filesystem::remove(tmp, ec);
      return false;
    }
  }

  // Solo se promociona a respaldo un guardado que se pueda leer: un archivo roto no
  // debe sustituir al .bak bueno
  if (std::filesystem::exists(main, ec) && readFile(main)) {
    std::filesystem::copy_file(main, bak, std::filesystem::copy_options::overwrite_existing, ec);
    if (ec) std::cerr << "[save] no se pudo actualizar el respaldo: " << ec.message() << std::endl;
  }

  std::filesystem::rename(tmp, main, ec);
  if (ec) {
    std::cerr << "[save] no se pudo renombrar el temporal: " << ec.message() << std::endl;
    std::filesystem::remove(tmp, ec);
    return false;
  }
  return true;
}

// Lee la ranura; si el archivo principal falta o esta roto, prueba el respaldo
inline std::optional<nlohmann::json> read(const std::string& dir, const std::string& slot) {
  if (!validSlot(slot)) return std::nullopt;
  if (auto j = readFile(slotPath(dir, slot))) return j;
  if (auto j = readFile(backupPath(dir, slot))) {
    std::cerr << "[save] guardado principal ilegible, usando el respaldo" << std::endl;
    return j;
  }
  return std::nullopt;
}

inline bool exists(const std::string& dir, const std::string& slot) {
  return read(dir, slot).has_value();
}

}  // namespace savefile
