#pragma once

#include <map>
#include <memory>
#include <string>

#include "AsepriteAtlas.hpp"

// Atlas cargados por assetId. Lo rellena AssetManager::addAtlas y lo consultan
// SceneLoader y los bindings de Lua (que no tienen acceso al AssetManager), igual
// que currentGameRoot().
inline std::map<std::string, std::shared_ptr<const aseprite::Atlas>>& atlasRegistry() {
  static std::map<std::string, std::shared_ptr<const aseprite::Atlas>> registry;
  return registry;
}
