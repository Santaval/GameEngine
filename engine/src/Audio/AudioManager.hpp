#pragma once
#include <SDL2/SDL_mixer.h>
#include <functional>
#include <map>
#include <string>

#include "../AssetManager/AssetManager.hpp"
#include "../Util/AudioBus.hpp"
#include "../Util/SpatialAudio.hpp"

// Audio con SDL_mixer: efectos y voces (Mix_Chunk en canales) y una sola musica
// de fondo (Mix_Music). Todo se llama desde el hilo principal; el unico codigo
// que corre en el hilo de audio es el callback de posicion, que solo usa atomics.
class AudioManager {
  public:
    static const int MAX_CHANNELS = 48;

  private:
    // Estado de una voz espacial (emisor): posicion, curvas y valores suavizados
    struct Spatial {
      float x = 0.0f;
      float y = 0.0f;
      spatial::SpatialParams params;
      // Entidad que mueve al emisor; -1 = posicion fija
      int followEntity = -1;
      // Distancia "mentirosa" que reemplaza a la real en el volumen; < 0 = sin override
      float overrideDist = -1.0f;
      // Ganancia y paneo suavizados; init = ya se aplico el primer valor sin suavizar
      float gain = 0.0f;
      float pan = 0.0f;
      bool init = false;
      // Ultimo paneo enviado al mezclador (-1 = ninguno): solo se llama si cambia
      int lastL = -1;
      int lastR = -1;
    };

    struct Voice {
      int channel = -1;
      std::string soundId;
      bool loop = false;
      // Volumen pedido por el script; el volumen final de una voz espacial es base * ganancia
      double baseVolume = 1.0;
      bool spatial = false;
      Spatial sp;
      // Bus al que pertenece la voz (define su volumen de bus y el ducking)
      audiobus::Bus bus = audiobus::Bus::Sfx;
      // Ultimo volumen enviado a Mix_Volume (-1 = ninguno): solo se llama si cambia
      int lastVol = -1;
    };

    AssetManager& assets;
    // Si Mix_OpenAudio falla el motor arranca igual y las llamadas no hacen nada
    bool available = false;
    int sampleRate = 0;
    int nextHandle = 1;
    std::map<int, Voice> voices;
    // Handle que ocupa cada canal (0 = libre)
    int channelOwner[MAX_CHANNELS] = {0};
    // Posicion del oyente (la fija Game cada frame)
    float listenerX = 0.0f;
    float listenerY = 0.0f;
    // Volumen de cada bus (0..1), indexado por audiobus::Bus
    float busVolume[audiobus::BUS_COUNT] = {1.0f, 1.0f, 1.0f, 1.0f};
    // Configuracion del ducking y su ganancia actual (1 = sin ducking)
    audiobus::DuckConfig duck;
    float duckGain = 1.0f;
    // Volumen pedido para la musica (antes del bus y del ducking)
    double musicBase = 1.0;
    // Ultimo volumen de musica enviado a Mix_VolumeMusic (-1 = ninguno)
    int lastMusicVol = -1;

    // Decodifica el chunk de un sonido stream=true la primera vez que suena
    Mix_Chunk* ensureChunk(SoundAsset& sound);
    // Libera los chunks stream que ya no usa ninguna voz
    void releaseUnusedStreams();
    const Voice* findVoice(int handle) const;
    Voice* findVoice(int handle);
    // Reproduce el sonido en un canal libre y registra la voz; 0 si falla
    int startVoice(const std::string& soundId, double volume, bool loop, audiobus::Bus bus);
    // Calcula ganancia y paneo de la voz y los manda al mezclador si cambiaron
    void applySpatial(Voice& voice, float dt, bool snap);
    // Ganancia de ducking que aplica un bus (1 si no esta en la mascara o no hay ducking)
    float duckFor(audiobus::Bus bus) const;
    // Volumen de bus * ducking de un bus
    double busGain(audiobus::Bus bus) const;
    // Manda a Mix_Volume el volumen final de una voz no espacial o espacial; solo si cambia
    void applyVoiceVolume(Voice& voice);
    // Manda a Mix_VolumeMusic la musica con bus y ducking; force ignora lastMusicVol
    void applyMusicVolume(bool force);

  public:
    explicit AudioManager(AssetManager& assetManager);
    ~AudioManager();

    // No fatal: devuelve false (y deja el audio como no-op) si no hay dispositivo
    bool init();
    // Cierra el mezclador. Los assets de audio se liberan antes con AssetManager::clearAll
    void shutdown();
    // Una vez por frame: descarta voces terminadas y libera chunks stream
    void update();
    // Detiene todas las voces y la musica (carga de escena y cierre). Conserva
    // los volumenes de bus y no reinicia el ducking
    void stopAll();

    // Devuelve un handle > 0, o 0 si el sonido no existe o no hay canal libre
    int playSound(const std::string& soundId, double volume, bool loop,
      audiobus::Bus bus = audiobus::Bus::Sfx);
    void stopSound(int handle, int fadeMs);
    void pauseSound(int handle);
    void resumeSound(int handle);
    void setSoundVolume(int handle, double volume);
    bool isPlaying(int handle) const;
    // Como playSound pero posicionado en el mundo: el volumen baja con la distancia
    // al oyente y el paneo sigue el desfase horizontal. Devuelve el mismo tipo de
    // handle (stop_sound, set_sound_volume, is_playing sirven igual). Con
    // followEntity >= 0 la posicion la resuelve updateSpatial cada frame
    int playSoundAt(const std::string& soundId, double volume, bool loop, float x, float y,
      const spatial::SpatialParams& params, int followEntity,
      audiobus::Bus bus = audiobus::Bus::Sfx);
    // Fija la posicion del emisor y deja de seguir a la entidad
    void setEmitterPosition(int handle, float x, float y);
    // Distancia que se usa en lugar de la real para el volumen; dist < 0 la quita
    void setEmitterDistanceOverride(int handle, float dist);
    // Posicion del oyente (sin tocar las voces)
    void setListener(float x, float y);
    // Una vez por frame: actualiza todas las voces espaciales. resolveFollow
    // devuelve false si la entidad ya no existe (la voz conserva su ultima posicion)
    void updateSpatial(float listenerX, float listenerY, double dt,
      const std::function<bool(int entityId, float& x, float& y)>& resolveFollow);
    // Corta las voces que siguen a esa entidad (se llama cuando muere)
    void stopEmittersFollowing(int entityId);
    // Segundos reproducidos; -1 si el handle ya no suena
    double soundPosition(int handle) const;
    // Segundos; -1 si el sonido no existe
    double soundDuration(const std::string& soundId);

    void playMusic(const std::string& musicId, int fadeMs, bool loop, double volume);
    void stopMusic(int fadeMs);

    // Volumen de un bus (0..1). Se guarda aunque el audio no este disponible
    void setBusVolume(audiobus::Bus bus, double volume);
    float getBusVolume(audiobus::Bus bus) const;
    // Configura el ducking; los valores fuera de rango se corrigen (amount 0..1, fadeMs >= 0)
    void setDuckConfig(const audiobus::DuckConfig& config);
    const audiobus::DuckConfig& getDuckConfig() const;
    // Vuelve al ducking por defecto (ambiente y musica, 35 %, 300 ms)
    void resetDuckConfig();
    // Una vez por frame: avanza la ganancia de ducking y actualiza los buses no espaciales y la musica
    void updateBuses(double dt);
};
