#pragma once

#include <string>
#include <glm/glm.hpp>
#include "../Util/SpatialAudio.hpp"

// Emisor de sonido pegado a la entidad: SpatialAudioSystem arranca la voz la
// primera vez y esta sigue a la entidad (volumen por distancia y paneo respecto
// al oyente). Muere con la entidad.
struct SoundEmitterComponent {
  std::string sound;
  float minDist;
  float maxDist;
  spatial::Rolloff rolloff;
  float volume;
  bool loop;
  // Desfase (px) respecto al centro de la entidad
  glm::vec2 offset;
  // Handle de la voz (0 = aun sin voz o no pudo sonar) y si ya se intento arrancar
  int handle = 0;
  bool started = false;

  SoundEmitterComponent(const std::string& sound = "", float minDist = 64.0f, float maxDist = 400.0f,
    spatial::Rolloff rolloff = spatial::Rolloff::Linear, float volume = 1.0f, bool loop = true,
    glm::vec2 offset = glm::vec2(0.0f, 0.0f)) {
      this->sound = sound;
      this->minDist = minDist;
      this->maxDist = maxDist;
      this->rolloff = rolloff;
      this->volume = volume;
      this->loop = loop;
      this->offset = offset;
  }
};
