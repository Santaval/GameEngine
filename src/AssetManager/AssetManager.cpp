#include "AssetManager.hpp"
#include <iostream>
#include <SDL2/SDL_image.h>

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
}

void AssetManager::addTexture(SDL_Renderer* renderer,
const std::string& textureId, const std::string& filePath) {

  SDL_Surface* surface = IMG_Load(filePath.c_str());
  SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, surface);
  SDL_FreeSurface(surface);

  this->textures.emplace(textureId, texture);

}

SDL_Texture* AssetManager::getTexture(const std::string& textureId) {
  return this->textures[textureId];
}