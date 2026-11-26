#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL_mixer.h>
#include <map>
#include <memory>
#include <string>

#include "../Animation/AsepriteAtlas.hpp"

// Efecto de sonido o voz. stream = true: el chunk no se decodifica al cargar sino
// la primera vez que suena (lo gestiona AudioManager); duration queda en 0 hasta entonces
struct SoundAsset {
  std::string path;
  bool stream = false;
  Mix_Chunk* chunk = nullptr;
  double duration = 0.0;
};

class AssetManager {
  private:
    std::map<std::string, SDL_Texture*> textures;
    std::map<std::string, TTF_Font*> fonts;
    std::map<std::string, std::shared_ptr<const aseprite::Atlas>> atlases;
    std::map<std::string, SoundAsset> sounds;
    std::map<std::string, Mix_Music*> music;
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

    // Atlas Aseprite (JSON). Se registra tambien en atlasRegistry() para los
    // bindings de Lua. Un error de lectura se informa por stderr y no registra nada
    void addAtlas(const std::string& assetId, const std::string& jsonPath);

    std::shared_ptr<const aseprite::Atlas> getAtlas(const std::string& assetId);

    // Sonidos cortos o voces. stream = true difiere la decodificacion al primer play_sound
    void addSound(const std::string& soundId, const std::string& filePath, bool stream);

    SoundAsset* getSound(const std::string& soundId);

    // Acceso a todos los sonidos para que AudioManager libere los chunks stream
    std::map<std::string, SoundAsset>& allSounds() { return this->sounds; }
    const std::map<std::string, SoundAsset>& allSounds() const { return this->sounds; }

    // Musica de fondo (una sola suena a la vez)
    void addMusic(const std::string& musicId, const std::string& filePath);

    Mix_Music* getMusic(const std::string& musicId);

    // Duracion en segundos de un chunk ya decodificado (con el formato abierto del mezclador)
    static double chunkDuration(Mix_Chunk* chunk);

};