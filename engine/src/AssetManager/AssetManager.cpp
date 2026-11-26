#include "AssetManager.hpp"
#include <iostream>
#include <SDL2/SDL_image.h>

#include "../Animation/AtlasRegistry.hpp"

AssetManager::AssetManager() {
  std::cout << "[AssetManager] Asser manager init" << std::endl;
}

AssetManager::~AssetManager() {
  std::cout << "[AssetManager] Asser manager destroy" << std::endl;
}

void AssetManager::clearAll() {
  for (auto texture : this->textures) {
    SDL_DestroyTexture(texture.second);
  }
  this->textures.clear();

  for (auto font : this->fonts) {
    TTF_CloseFont(font.second);
  }
  this->fonts.clear();

  this->atlases.clear();
  atlasRegistry().clear();
}

void AssetManager::addTexture(SDL_Renderer* renderer,
const std::string& textureId, const std::string& filePath) {
  // Al recargar una escena los ids ya existen: cargarlos de nuevo filtraria
  // la textura (emplace no reemplaza)
  if (this->textures.count(textureId)) return;

  SDL_Surface* surface = IMG_Load(filePath.c_str());
  SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, surface);
  SDL_FreeSurface(surface);

  this->textures.emplace(textureId, texture);

}

// Usa find(): operator[] insertaría un nullptr silencioso si el id no existe
SDL_Texture* AssetManager::getTexture(const std::string& textureId) {
  auto texture = this->textures.find(textureId);

  if (texture == this->textures.end()) {
    std::cout << "[AssetManager] Texture not found: " << textureId << std::endl;
    return nullptr;
  }

  return texture->second;
}

void AssetManager::addFont(const std::string& fontId,
const std::string& filePath, int fontSize) {
  if (this->fonts.count(fontId)) return;

  TTF_Font* font = TTF_OpenFont(filePath.c_str(), fontSize);

  if (!font) {
    std::cout << "[AssetManager] Error opening font " << filePath
      << ": " << TTF_GetError() << std::endl;
    return;
  }

  this->fonts.emplace(fontId, font);

}

TTF_Font* AssetManager::getFont(const std::string& fontId) {
  auto font = this->fonts.find(fontId);

  if (font == this->fonts.end()) {
    std::cout << "[AssetManager] Font not found: " << fontId << std::endl;
    return nullptr;
  }

  return font->second;
}

void AssetManager::addAtlas(const std::string& assetId, const std::string& jsonPath) {
  if (this->atlases.count(assetId)) return;

  aseprite::Result result = aseprite::loadFile(jsonPath);
  if (!result.ok) {
    std::cerr << "[AssetManager] Error loading atlas " << assetId << ": "
      << result.error << std::endl;
    return;
  }

  auto atlas = std::make_shared<const aseprite::Atlas>(std::move(result.atlas));
  this->atlases.emplace(assetId, atlas);
  atlasRegistry()[assetId] = atlas;
}

std::shared_ptr<const aseprite::Atlas> AssetManager::getAtlas(const std::string& assetId) {
  auto atlas = this->atlases.find(assetId);

  if (atlas == this->atlases.end()) {
    std::cout << "[AssetManager] Atlas not found: " << assetId << std::endl;
    return nullptr;
  }

  return atlas->second;
}
