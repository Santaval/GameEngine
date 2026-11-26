#pragma once
#include <SDL2/SDL_mixer.h>
#include <map>
#include <string>

#include "../AssetManager/AssetManager.hpp"

// Audio con SDL_mixer: efectos y voces (Mix_Chunk en canales) y una sola musica
// de fondo (Mix_Music). Todo se llama desde el hilo principal; el unico codigo
// que corre en el hilo de audio es el callback de posicion, que solo usa atomics.
class AudioManager {
  public:
    static const int MAX_CHANNELS = 48;

  private:
    struct Voice {
      int channel = -1;
      std::string soundId;
      bool loop = false;
    };

    AssetManager& assets;
    // Si Mix_OpenAudio falla el motor arranca igual y las llamadas no hacen nada
    bool available = false;
    int sampleRate = 0;
    int nextHandle = 1;
    std::map<int, Voice> voices;
    // Handle que ocupa cada canal (0 = libre)
    int channelOwner[MAX_CHANNELS] = {0};

    // Decodifica el chunk de un sonido stream=true la primera vez que suena
    Mix_Chunk* ensureChunk(SoundAsset& sound);
    // Libera los chunks stream que ya no usa ninguna voz
    void releaseUnusedStreams();
    const Voice* findVoice(int handle) const;

  public:
    explicit AudioManager(AssetManager& assetManager);
    ~AudioManager();

    // No fatal: devuelve false (y deja el audio como no-op) si no hay dispositivo
    bool init();
    // Cierra el mezclador. Los assets de audio se liberan antes con AssetManager::clearAll
    void shutdown();
    // Una vez por frame: descarta voces terminadas y libera chunks stream
    void update();
    // Detiene todas las voces y la musica (carga de escena y cierre)
    void stopAll();

    // Devuelve un handle > 0, o 0 si el sonido no existe o no hay canal libre
    int playSound(const std::string& soundId, double volume, bool loop);
    void stopSound(int handle, int fadeMs);
    void setSoundVolume(int handle, double volume);
    bool isPlaying(int handle) const;
    // Segundos reproducidos; -1 si el handle ya no suena
    double soundPosition(int handle) const;
    // Segundos; -1 si el sonido no existe
    double soundDuration(const std::string& soundId);

    void playMusic(const std::string& musicId, int fadeMs, bool loop, double volume);
    void stopMusic(int fadeMs);
};
