#pragma once
#include <SDL2/SDL.h>
#include <map>
#include <string>

class AssetManager {
  private:
    std::map<std::string, SDL_Texture*> textures;
  public:
    AssetManager();
    ~AssetManager();

    void clearAll();

    void addTexture(SDL_Renderer* renderer,
      const std::string& assetId, const std::string& filePath);
    
    SDL_Texture* getTexture(const std::string& textureId);


};