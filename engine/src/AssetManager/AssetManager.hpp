#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <map>
#include <string>

class AssetManager {
  private:
    std::map<std::string, SDL_Texture*> textures;
    std::map<std::string, TTF_Font*> fonts;
  public:
    AssetManager();
    ~AssetManager();

    void clearAll();

    void addTexture(SDL_Renderer* renderer,
      const std::string& assetId, const std::string& filePath);

    SDL_Texture* getTexture(const std::string& textureId);

    // El tamaño queda fijo al abrir la fuente: un fontId = un tamaño
    void addFont(const std::string& fontId, const std::string& filePath, int fontSize);

    TTF_Font* getFont(const std::string& fontId);

};