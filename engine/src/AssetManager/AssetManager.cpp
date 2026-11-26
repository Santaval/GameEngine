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

  // Los canales y la musica ya tienen que estar detenidos (AudioManager::stopAll):
  // liberar un chunk que suena rompe el hilo de audio
  for (auto& sound : this->sounds) {
    if (sound.second.chunk) Mix_FreeChunk(sound.second.chunk);
  }
  this->sounds.clear();

  for (auto& track : this->music) {
    Mix_FreeMusic(track.second);
  }
  this->music.clear();
}

void AssetManager::addTexture(SDL_Renderer* renderer,
const std::string& textureId, const std::string& filePath) {
  // Al recargar una escena los ids ya existen: cargarlos de nuevo filtraria
  // la textura (emplace no reemplaza)
  if (this->textures.count(textureId)) return;

  SDL_Surface* surface = IMG_Load(filePath.c_str());
  // Sin imagen no se guarda un nullptr: asi un id fallido se vuelve a intentar
  // y getTexture lo informa como no encontrado
  if (surface == nullptr) {
    std::cout << "[AssetManager] Error loading texture " << filePath << ": " << IMG_GetError() << std::endl;
    return;
  }
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


double AssetManager::chunkDuration(Mix_Chunk* chunk) {
  int freq = 0;
  int channels = 0;
  Uint16 format = 0;
  if (!chunk || Mix_QuerySpec(&freq, &format, &channels) == 0) return 0.0;

  int frameBytes = channels * ((format & 0xFF) / 8);
  if (frameBytes <= 0 || freq <= 0) return 0.0;
  return static_cast<double>(chunk->alen) / (static_cast<double>(frameBytes) * freq);
}

void AssetManager::addSound(const std::string& soundId,
const std::string& filePath, bool stream) {
  if (this->sounds.count(soundId)) return;

  SoundAsset sound;
  sound.path = filePath;
  sound.stream = stream;

  // stream = true: solo se registra la ruta, el chunk se decodifica al primer play
  if (!stream) {
    sound.chunk = Mix_LoadWAV(filePath.c_str());
    if (!sound.chunk) {
      std::cout << "[AssetManager] Error loading sound " << filePath
        << ": " << Mix_GetError() << std::endl;
      return;
    }
    sound.duration = chunkDuration(sound.chunk);
  }

  this->sounds.emplace(soundId, sound);
}

SoundAsset* AssetManager::getSound(const std::string& soundId) {
  auto sound = this->sounds.find(soundId);

  if (sound == this->sounds.end()) {
    std::cout << "[AssetManager] Sound not found: " << soundId << std::endl;
    return nullptr;
  }

  return &sound->second;
}

void AssetManager::addMusic(const std::string& musicId, const std::string& filePath) {
  if (this->music.count(musicId)) return;

  Mix_Music* track = Mix_LoadMUS(filePath.c_str());

  if (!track) {
    std::cout << "[AssetManager] Error loading music " << filePath
      << ": " << Mix_GetError() << std::endl;
    return;
  }

  this->music.emplace(musicId, track);
}

Mix_Music* AssetManager::getMusic(const std::string& musicId) {
  auto track = this->music.find(musicId);

  if (track == this->music.end()) {
    std::cout << "[AssetManager] Music not found: " << musicId << std::endl;
    return nullptr;
  }

  return track->second;
}
