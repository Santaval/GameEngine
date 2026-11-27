#include "AudioManager.hpp"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <iostream>
#include <set>

namespace {
  // Frames mezclados por canal. Los escribe el hilo de audio y los lee el principal
  std::atomic<long long> playedFrames[AudioManager::MAX_CHANNELS];
  // Bytes por frame del formato abierto (canales * bytes por muestra)
  std::atomic<int> bytesPerFrame{4};

  // Efecto "passthrough": no toca el audio, solo cuenta cuantos frames pasaron por el canal
  void positionEffect(int channel, void* /*stream*/, int len, void* /*udata*/) {
    if (channel < 0 || channel >= AudioManager::MAX_CHANNELS) return;
    int bpf = bytesPerFrame.load();
    if (bpf <= 0) return;
    playedFrames[channel].fetch_add(len / bpf);
  }

  int toMixVolume(double volume) {
    return static_cast<int>(std::clamp(volume, 0.0, 1.0) * MIX_MAX_VOLUME);
  }
}

AudioManager::AudioManager(AssetManager& assetManager) : assets(assetManager) {}

AudioManager::~AudioManager() {
  this->shutdown();
}

bool AudioManager::init() {
  int wanted = MIX_INIT_OGG | MIX_INIT_MP3;
  int got = Mix_Init(wanted);
  if ((got & wanted) != wanted) {
    std::cout << "[Audio] Warning: missing decoder support (OGG/MP3): " << Mix_GetError() << std::endl;
  }

  // 48000 Hz con buffer de 1024 muestras (~21 ms): la posicion queda dentro de +-50 ms
  if (Mix_OpenAudio(48000, MIX_DEFAULT_FORMAT, 2, 1024) != 0) {
    std::cout << "[Audio] Error opening audio device, audio disabled: " << Mix_GetError() << std::endl;
    Mix_Quit();
    return false;
  }

  Mix_AllocateChannels(MAX_CHANNELS);

  int freq = 0;
  int channels = 0;
  Uint16 format = 0;
  if (Mix_QuerySpec(&freq, &format, &channels) == 0) {
    std::cout << "[Audio] Error querying audio spec: " << Mix_GetError() << std::endl;
    Mix_CloseAudio();
    Mix_Quit();
    return false;
  }
  this->sampleRate = freq;
  bytesPerFrame.store(channels * ((format & 0xFF) / 8));

  this->available = true;
  std::cout << "[Audio] Audio init: " << freq << " Hz, " << channels << " channels" << std::endl;
  return true;
}

void AudioManager::shutdown() {
  if (!this->available) return;

  this->stopAll();
  this->available = false;
  Mix_CloseAudio();
  Mix_Quit();
}

Mix_Chunk* AudioManager::ensureChunk(SoundAsset& sound) {
  if (sound.chunk) return sound.chunk;

  sound.chunk = Mix_LoadWAV(sound.path.c_str());
  if (!sound.chunk) {
    std::cout << "[Audio] Error decoding sound " << sound.path << ": " << Mix_GetError() << std::endl;
    return nullptr;
  }
  sound.duration = AssetManager::chunkDuration(sound.chunk);
  return sound.chunk;
}

void AudioManager::releaseUnusedStreams() {
  std::set<std::string> inUse;
  for (const auto& voice : this->voices) {
    inUse.insert(voice.second.soundId);
  }

  for (auto& entry : this->assets.allSounds()) {
    SoundAsset& sound = entry.second;
    if (sound.stream && sound.chunk && inUse.count(entry.first) == 0) {
      Mix_FreeChunk(sound.chunk);
      sound.chunk = nullptr;
    }
  }
}

const AudioManager::Voice* AudioManager::findVoice(int handle) const {
  auto it = this->voices.find(handle);
  if (it == this->voices.end()) return nullptr;
  const Voice& voice = it->second;
  if (voice.channel < 0 || voice.channel >= MAX_CHANNELS) return nullptr;
  if (this->channelOwner[voice.channel] != handle) return nullptr;
  return &voice;
}

AudioManager::Voice* AudioManager::findVoice(int handle) {
  return const_cast<Voice*>(static_cast<const AudioManager*>(this)->findVoice(handle));
}

void AudioManager::update() {
  if (!this->available) return;

  bool finished = false;
  for (auto it = this->voices.begin(); it != this->voices.end();) {
    int channel = it->second.channel;
    if (!Mix_Playing(channel)) {
      if (this->channelOwner[channel] == it->first) this->channelOwner[channel] = 0;
      it = this->voices.erase(it);
      finished = true;
    } else {
      ++it;
    }
  }

  if (finished) this->releaseUnusedStreams();
}

void AudioManager::stopAll() {
  if (!this->available) return;

  Mix_HaltChannel(-1);
  Mix_HaltMusic();
  this->voices.clear();
  std::fill(std::begin(this->channelOwner), std::end(this->channelOwner), 0);
  this->releaseUnusedStreams();
}

float AudioManager::duckFor(audiobus::Bus bus) const {
  // La voz nunca se atenua a si misma, aunque alguien la ponga en la mascara
  if (bus == audiobus::Bus::Voice) return 1.0f;
  if (!this->duck.enabled || !this->duck.buses[static_cast<int>(bus)]) return 1.0f;
  return this->duckGain;
}

double AudioManager::busGain(audiobus::Bus bus) const {
  return this->busVolume[static_cast<int>(bus)] * this->duckFor(bus);
}

void AudioManager::applyVoiceVolume(Voice& voice) {
  double gain = voice.baseVolume * this->busGain(voice.bus);
  if (voice.spatial) gain *= voice.sp.gain;

  int vol = toMixVolume(gain);
  if (vol != voice.lastVol) {
    Mix_Volume(voice.channel, vol);
    voice.lastVol = vol;
  }
}

void AudioManager::applyMusicVolume(bool force) {
  int vol = toMixVolume(this->musicBase * this->busGain(audiobus::Bus::Music));
  if (!force && vol == this->lastMusicVol) return;

  Mix_VolumeMusic(vol);
  this->lastMusicVol = vol;
}

void AudioManager::setBusVolume(audiobus::Bus bus, double volume) {
  // Se guarda aunque no haya audio: asi el valor de los ajustes se conserva igual
  this->busVolume[static_cast<int>(bus)] = static_cast<float>(std::clamp(volume, 0.0, 1.0));
  if (!this->available) return;

  // Las voces espaciales las actualiza applySpatial en el siguiente frame
  for (auto& entry : this->voices) {
    Voice& voice = entry.second;
    if (voice.spatial || voice.bus != bus) continue;
    if (voice.channel < 0 || voice.channel >= MAX_CHANNELS) continue;
    if (this->channelOwner[voice.channel] != entry.first) continue;

    this->applyVoiceVolume(voice);
  }
  if (bus == audiobus::Bus::Music) this->applyMusicVolume(false);
}

float AudioManager::getBusVolume(audiobus::Bus bus) const {
  return this->busVolume[static_cast<int>(bus)];
}

void AudioManager::setDuckConfig(const audiobus::DuckConfig& config) {
  this->duck = config;
  this->duck.amount = std::clamp(config.amount, 0.0f, 1.0f);
  this->duck.fadeMs = std::max(config.fadeMs, 0);
}

const audiobus::DuckConfig& AudioManager::getDuckConfig() const {
  return this->duck;
}

void AudioManager::resetDuckConfig() {
  this->duck = audiobus::DuckConfig();
}

void AudioManager::updateBuses(double dt) {
  if (!this->available) return;

  // Hay voz sonando si alguna voz del bus Voice sigue en un canal propio
  bool voiceActive = false;
  for (const auto& entry : this->voices) {
    const Voice& voice = entry.second;
    if (voice.bus != audiobus::Bus::Voice) continue;
    if (voice.channel < 0 || voice.channel >= MAX_CHANNELS) continue;
    if (this->channelOwner[voice.channel] != entry.first) continue;
    if (Mix_Playing(voice.channel)) {
      voiceActive = true;
      break;
    }
  }

  float target = (this->duck.enabled && voiceActive) ? this->duck.amount : 1.0f;
  this->duckGain = audiobus::duckStep(this->duckGain, target, dt, this->duck);

  for (auto& entry : this->voices) {
    Voice& voice = entry.second;
    if (voice.spatial) continue;
    if (voice.channel < 0 || voice.channel >= MAX_CHANNELS) continue;
    if (this->channelOwner[voice.channel] != entry.first) continue;

    this->applyVoiceVolume(voice);
  }
  this->applyMusicVolume(false);
}

int AudioManager::startVoice(const std::string& soundId, double volume, bool loop, audiobus::Bus bus) {
  SoundAsset* sound = this->assets.getSound(soundId);
  if (!sound) return 0;

  Mix_Chunk* chunk = this->ensureChunk(*sound);
  if (!chunk) return 0;

  int channel = Mix_PlayChannel(-1, chunk, loop ? -1 : 0);
  if (channel < 0 || channel >= MAX_CHANNELS) {
    std::cout << "[Audio] No free channel for sound " << soundId << std::endl;
    return 0;
  }

  // El canal estaba ocupado por una voz ya terminada que update() aun no descarto
  int previous = this->channelOwner[channel];
  if (previous != 0) this->voices.erase(previous);

  Mix_UnregisterAllEffects(channel);
  playedFrames[channel].store(0);
  Mix_RegisterEffect(channel, positionEffect, nullptr, nullptr);
  // Volumen inicial con el bus y el ducking del momento; applyVoiceVolume lo mantiene
  int initial = toMixVolume(volume * this->busGain(bus));
  Mix_Volume(channel, initial);

  int handle = this->nextHandle++;
  Voice voice;
  voice.channel = channel;
  voice.soundId = soundId;
  voice.loop = loop;
  voice.baseVolume = volume;
  voice.bus = bus;
  voice.lastVol = initial;
  this->voices[handle] = voice;
  this->channelOwner[channel] = handle;
  return handle;
}

int AudioManager::playSound(const std::string& soundId, double volume, bool loop, audiobus::Bus bus) {
  if (!this->available) return 0;

  return this->startVoice(soundId, volume, loop, bus);
}

int AudioManager::playSoundAt(const std::string& soundId, double volume, bool loop, float x, float y,
    const spatial::SpatialParams& params, int followEntity, audiobus::Bus bus) {
  if (!this->available) return 0;

  // Arranca en silencio: applySpatial fija el volumen real antes del siguiente buffer
  int handle = this->startVoice(soundId, 0.0, loop, bus);
  if (handle == 0) return 0;

  Voice& voice = this->voices[handle];
  voice.baseVolume = volume;
  voice.spatial = true;
  voice.sp.x = x;
  voice.sp.y = y;
  voice.sp.params = params;
  voice.sp.followEntity = followEntity;
  // Primer valor sin suavizar: la voz no sube desde cero
  this->applySpatial(voice, 0.0f, true);
  return handle;
}

void AudioManager::applySpatial(Voice& voice, float dt, bool snap) {
  Spatial& sp = voice.sp;

  float dx = sp.x - this->listenerX;
  float dy = sp.y - this->listenerY;
  float dist = std::sqrt(dx * dx + dy * dy);

  // El override solo miente en el volumen: el paneo conserva la direccion real
  float volDist = sp.overrideDist >= 0.0f ? sp.overrideDist : dist;
  float targetGain = spatial::spatialGain(volDist, sp.params);
  float targetPan = spatial::spatialPan(dx, dist, sp.params);

  if (snap || !sp.init) {
    sp.gain = targetGain;
    sp.pan = targetPan;
    sp.init = true;
  } else {
    // Constante de tiempo de 0.08 s; dt acotado para que un tiron no sea un salto
    float alpha = spatial::smoothAlpha(std::min(dt, 0.1f), 0.08f);
    sp.gain += (targetGain - sp.gain) * alpha;
    sp.pan += (targetPan - sp.pan) * alpha;
  }

  // Volumen final = base * bus * ducking * ganancia espacial (solo cambia si el valor cambia)
  this->applyVoiceVolume(voice);

  int left = 255;
  int right = 255;
  spatial::panToGains(sp.pan, left, right);
  if (left != sp.lastL || right != sp.lastR) {
    Mix_SetPanning(voice.channel, static_cast<Uint8>(left), static_cast<Uint8>(right));
    sp.lastL = left;
    sp.lastR = right;
  }
}

void AudioManager::setEmitterPosition(int handle, float x, float y) {
  if (!this->available) return;

  Voice* voice = this->findVoice(handle);
  if (!voice || !voice->spatial) return;

  voice->sp.x = x;
  voice->sp.y = y;
  voice->sp.followEntity = -1;
}

void AudioManager::setEmitterDistanceOverride(int handle, float dist) {
  if (!this->available) return;

  Voice* voice = this->findVoice(handle);
  if (!voice || !voice->spatial) return;

  voice->sp.overrideDist = dist < 0.0f ? -1.0f : dist;
}

void AudioManager::setListener(float x, float y) {
  this->listenerX = x;
  this->listenerY = y;
}

void AudioManager::updateSpatial(float lx, float ly, double dt,
    const std::function<bool(int entityId, float& x, float& y)>& resolveFollow) {
  if (!this->available) return;

  this->listenerX = lx;
  this->listenerY = ly;

  for (auto& entry : this->voices) {
    Voice& voice = entry.second;
    if (!voice.spatial) continue;
    // Voz terminada que update() aun no descarto: su canal puede ser de otra voz
    if (voice.channel < 0 || voice.channel >= MAX_CHANNELS) continue;
    if (this->channelOwner[voice.channel] != entry.first) continue;

    if (voice.sp.followEntity >= 0 && resolveFollow) {
      float x = voice.sp.x;
      float y = voice.sp.y;
      if (resolveFollow(voice.sp.followEntity, x, y)) {
        voice.sp.x = x;
        voice.sp.y = y;
      }
    }

    this->applySpatial(voice, static_cast<float>(dt), false);
  }
}

void AudioManager::stopEmittersFollowing(int entityId) {
  if (!this->available) return;

  for (auto& entry : this->voices) {
    const Voice& voice = entry.second;
    if (!voice.spatial || voice.sp.followEntity != entityId) continue;
    if (voice.channel < 0 || voice.channel >= MAX_CHANNELS) continue;
    if (this->channelOwner[voice.channel] != entry.first) continue;

    // update() descarta la voz en el siguiente frame
    Mix_HaltChannel(voice.channel);
  }
}

void AudioManager::stopSound(int handle, int fadeMs) {
  if (!this->available) return;

  const Voice* voice = this->findVoice(handle);
  if (!voice) return;

  if (fadeMs > 0) Mix_FadeOutChannel(voice->channel, fadeMs);
  else Mix_HaltChannel(voice->channel);
}

void AudioManager::pauseSound(int handle) {
  if (!this->available) return;

  const Voice* voice = this->findVoice(handle);
  if (!voice || voice->channel < 0 || voice->channel >= MAX_CHANNELS) return;
  if (this->channelOwner[voice->channel] != handle) return;
  // El canal sigue "sonando" para Mix_Playing: la voz y el ducking se conservan
  Mix_Pause(voice->channel);
}

void AudioManager::resumeSound(int handle) {
  if (!this->available) return;

  const Voice* voice = this->findVoice(handle);
  if (!voice || voice->channel < 0 || voice->channel >= MAX_CHANNELS) return;
  if (this->channelOwner[voice->channel] != handle) return;
  Mix_Resume(voice->channel);
}

void AudioManager::setSoundVolume(int handle, double volume) {
  if (!this->available) return;

  Voice* voice = this->findVoice(handle);
  if (!voice) return;

  // En una voz espacial solo cambia la base: updateSpatial aplica base * ganancia
  voice->baseVolume = volume;
  if (!voice->spatial) this->applyVoiceVolume(*voice);
}

bool AudioManager::isPlaying(int handle) const {
  if (!this->available) return false;

  const Voice* voice = this->findVoice(handle);
  return voice != nullptr && Mix_Playing(voice->channel) != 0;
}

double AudioManager::soundPosition(int handle) const {
  if (!this->available || this->sampleRate <= 0) return -1.0;

  const Voice* voice = this->findVoice(handle);
  if (!voice || !Mix_Playing(voice->channel)) return -1.0;

  double seconds = static_cast<double>(playedFrames[voice->channel].load()) / this->sampleRate;

  auto sound = this->assets.allSounds().find(voice->soundId);
  if (sound != this->assets.allSounds().end() && sound->second.duration > 0.0) {
    double duration = sound->second.duration;
    // En bucle la posicion vuelve a 0; sin bucle el ultimo buffer puede pasarse
    seconds = voice->loop ? std::fmod(seconds, duration) : std::min(seconds, duration);
  }
  return seconds;
}

double AudioManager::soundDuration(const std::string& soundId) {
  if (!this->available) return -1.0;

  SoundAsset* sound = this->assets.getSound(soundId);
  if (!sound) return -1.0;

  // Los sonidos stream no conocen su duracion hasta decodificarlos la primera vez
  if (sound->duration <= 0.0) this->ensureChunk(*sound);
  if (!sound->chunk && sound->duration <= 0.0) return -1.0;

  double duration = sound->duration;
  // Un stream sin ninguna voz activa no tiene por que quedarse en memoria
  this->releaseUnusedStreams();
  return duration;
}

void AudioManager::playMusic(const std::string& musicId, int fadeMs, bool loop, double volume) {
  if (!this->available) return;

  Mix_Music* music = this->assets.getMusic(musicId);
  if (!music) return;

  // Solo hay un slot de musica: se corta la anterior antes de empezar
  Mix_HaltMusic();
  this->musicBase = volume;
  this->applyMusicVolume(true);

  int result = fadeMs > 0
    ? Mix_FadeInMusic(music, loop ? -1 : 1, fadeMs)
    : Mix_PlayMusic(music, loop ? -1 : 1);
  if (result != 0) {
    std::cout << "[Audio] Error playing music " << musicId << ": " << Mix_GetError() << std::endl;
  }
}

void AudioManager::stopMusic(int fadeMs) {
  if (!this->available) return;

  if (fadeMs > 0) Mix_FadeOutMusic(fadeMs);
  else Mix_HaltMusic();
}
